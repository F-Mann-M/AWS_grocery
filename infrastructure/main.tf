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
    cidr_blocks = ["0.0.0.0/0"]
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
    security_groups = [aws_security_group.ec2_sg.id] # just let EC2
  }
}


### RESOURCE ###

# EC2 Instance
resource "aws_instance" "app_server" {
  ami           = "ami-096a4fdbcf530d8e0" # Amazon Linux 2023
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

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


# OUTPUTS
output "ec2_public_ip" {
  description = "Public ip of EC2 instance"
  value       = aws_instance.app_server.public_ip
}

output "rds_endpoint" {
  description = "Database Endpoint"
  value       = aws_db_instance.postgres_db.address
}