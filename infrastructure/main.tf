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

# use standard VPC
data "aws_vpc" "default" {
  default = true
}


### SECURITY GROUPS ###

# Get your current IP address
data "http" "myip" {
  url = "https://ipv4.icanhazip.com"
}

# Security Group for instance
resource "aws_security_group" "ec2_sg" {
  name        = "grocerymate-server-sg"
  description = "accepts HTTP and SSH traffic into the EC2 instance"
  vpc_id      = data.aws_vpc.default.id

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
  vpc_id      = data.aws_vpc.default.id

  # inbound: Port 5432 (Postgres)
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id] # just let EC2 connect to the database
  }
}



### IAM ROLE FOR EC2 ###

# Create IAM role for EC2 instance
resource "aws_iam_role" "ec2_s3_role" {
  name = "grocerymate-ec2-s3-role"

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

# Attache S3 predefined policy to the role (allows EC2 to access S3)
resource "aws_iam_role_policy_attachment" "s3_full_access" {
  role       = aws_iam_role.ec2_s3_role.name # point to the actual role name created above
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess" # predifined AWS policy for full S3 access
}

# Create an instance profile and attach it to the role 
resource "aws_iam_instance_profile" "ec2_s3_profile" {
  name = "grocerymate-ec2-s3-profile"
  role = aws_iam_role.ec2_s3_role.name
}


### RESOURCE ###

### EC2 Instance ###

resource "aws_instance" "app_server" {
  ami           = "ami-096a4fdbcf530d8e0" # Amazon Linux 2023
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  iam_instance_profile = aws_iam_instance_profile.ec2_s3_profile.name # attach the instance profile to EC2

  key_name = var.PRIVATE_KEY_NAME # use your own key pair name to be able to SSH into the instance

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
  username = "postgres_admin"
  password = var.DB_PASSWORD

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
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
    Environment = "Dev"
  }
}


# S3 Bucket for storing user avatars
resource "aws_s3_bucket" "avatars" {
  bucket = "grocerymate-avatars-24111983"

  tags = {
    Name        = "grocerymate-avatars"
    Environment = "Dev"
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
  description = "Database Endpoint"
  value       = aws_db_instance.postgres_db.address
}

# # Output the URL of the ECR repository so GitHub Actions can use it later to push Docker images
# output "ecr_repository_url" {
#   description = "The URL of the ECR repository" 
#   value       = aws_ecr_repository.grocerymate_repo.repository_url
# }