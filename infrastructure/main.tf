terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.35.1"
    }
  }
}

provider "aws" {
  region = "eu-central-1" # Frankfurt
}


### NETWORKING RESOURCES ###

# Custom VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "grocerymate-vpc"
  }
}

# Internet gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "grocerymate-igw"
  }
}

# Public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-central-1a"

  tags = {
    Name = "grocerymate-public-subnet"
  }
}

# Route table for public subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "public_subnet_rt"
  }
}

# Route table association for public subnet
resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Private subnet for RDS
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "grocerymate-private-subnet-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-central-1b"

  tags = {
    Name = "grocerymate-private-subnet-2"
  }
}

# Route table for private subnets (no internet access, just for RDS)
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "private_subnet_rt"
  }
} 

# Associate private subnet 1 with the private route table
resource "aws_route_table_association" "private_rt_assoc_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt.id
}

# Associate private subnet 2 with the private route table
resource "aws_route_table_association" "private_rt_assoc_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}

# RDS Subnet Group (allows RDS to use the private subnets)
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "grocerymate-rds-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name = "grocerymate-rds-subnet-group"
  }
}


### SECURITY GROUPS ###

# Get current IP address
data "http" "myip" {
  url = "https://checkip.amazonaws.com"
}

# Security Group for instance
resource "aws_security_group" "ec2_sg" {
  name        = "grocerymate-server-sg"
  description = "accepts HTTP and SSH traffic into the EC2 instance"
  vpc_id      = aws_vpc.main.id

  # inbound SSH on prot 22
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    # only allow SSH from your own IP for security. 
    # Github Actions will update the ec2_sg dynamically during deployment, to gain temporary access.
    cidr_blocks = ["${chomp(data.http.myip.response_body)}/32"] 
    
  }

  # inbound app (Port 5000 for GroceryMate)
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # all traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  name        = "grocerymate-database-sg"
  description = "accepts traffic only from the EC2 instance"
  vpc_id      = aws_vpc.main.id

  # inbound: Port 5432 (Postgres)
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id] # just let EC2 connect to the database
  }
}


### IAM ROLE FOR EC2 ###

# IAM role for EC2 instance to access S3 and ECR
resource "aws_iam_role" "ec2_app_role" {
  name = "grocerymate-ec2-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach S3 predefined policy to the role (allows EC2 to access S3)
resource "aws_iam_role_policy_attachment" "s3_full_access" {
  role       = aws_iam_role.ec2_app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Grant the EC2 instance permission to pull Docker images from ECR
resource "aws_iam_role_policy_attachment" "ecr_read_access" {
  role       = aws_iam_role.ec2_app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Create an instance profile and attach it to the role 
resource "aws_iam_instance_profile" "ec2_app_profile" {
  name = "grocerymate-ec2-app-profile"
  role = aws_iam_role.ec2_app_role.name
}


### RESOURCE ###

### EC2 Instance ###

resource "aws_instance" "app_server" {
  ami           = "ami-096a4fdbcf530d8e0" # Amazon Linux 2023
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet.id
  associate_public_ip_address = true # ensure the instance gets a public IP

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  iam_instance_profile = aws_iam_instance_profile.ec2_app_profile.name 

  key_name = var.PRIVATE_KEY_NAME # use your own key pair name to be able to SSH into the instance

  # use amazon-ecr-credential-helper to allow EC2 to pull images from ECR without needing to manage AWS credentials on the instance.
  user_data = <<-EOF
              #!/bin/bash
              # Update OS and install Docker, Postgres Client, and ECR Credential Helper
              yum update -y
              yum install -y docker postgresql15 amazon-ecr-credential-helper
              
              # Enable and start Docker service
              systemctl enable docker
              systemctl start docker

              # Configure Docker for the root user (for your 'sudo docker' commands)
              mkdir -p /root/.docker
              echo '{"credsStore": "ecr-login"}' > /root/.docker/config.json
              EOF

  tags = {
    Name = "Grocerymate-App-Server"
  }
}

# RDS Database (postgresql)
resource "aws_db_instance" "postgres_db" {
  identifier        = "grocerymate-db"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = "db.t3.micro" #
  allocated_storage = 20 # min size in GB

  db_name  = "grocerymate_db"
  username = var.DB_USERNAME
  password = var.DB_PASSWORD

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
  
  publicly_accessible    = false # keep it private
  skip_final_snapshot    = true  # don't make a final snapshot
}


# ECR Repository for Docker Images
resource "aws_ecr_repository" "grocerymate_repo" { # terraform private name for the resource
  name                 = "grocerymate-app" # actual name of the repository in ECR in AWS
  image_tag_mutability = "MUTABLE" # allow overwriting tags

  image_scanning_configuration {
    scan_on_push = true # automatically scan images for vulnerabilities when pushed (AWS feature)
  }

  tags = {
    Name        = "grocerymate-app-repo"
  }
}


# S3 Bucket for storing user avatars
resource "aws_s3_bucket" "avatars" {
  bucket = "grocerymate-avatars-24111983"

  tags = {
    Name        = "grocerymate-avatars"
  }
}


### OUTPUTS ###

#output the public IP of the EC2 instance
output "ec2_public_ip" {
  description = "Public ip of EC2 instance"
  value       = aws_instance.app_server.public_ip
}

# output the RDS endpoint so the application can connect to it
output "rds_endpoint" {
description = "Database Endpoint copy and paste this into github secrets PSOTGRES_HOST"
  value       = aws_db_instance.postgres_db.address
}

output "ssh_connection_command" {
  description = "Command to SSH into the EC2 instance"
  value       = "ssh -i <private_key_name>.pem ec2-user@${aws_instance.app_server.public_ip}"
}

# # Output the URL of the ECR repository so GitHub Actions can use it later to push Docker images
# output "ecr_repository_url" {
#   description = "The URL of the ECR repository" 
#   value       = aws_ecr_repository.grocerymate_repo.repository_url
# }