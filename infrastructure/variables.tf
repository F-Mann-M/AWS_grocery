variable "DB_PASSWORD" {
  description = "Master password for grocerymate db"
  type        = string
  sensitive   = true # hide password
}

variable "GIT_USERNAME" {
  description = "GitHub username for pushing to ECR "
  type        = string
  sensitive   = true # hide password
}

variable "PRIVATE_KEY_NAME" {
  description = "Name of the private key pair for SSH access to EC2 instance"
  type        = string
  sensitive   = true # hide password
}

