variable "DB_PASSWORD" {
  description = "Master password for grocerymate db"
  type        = string
  sensitive   = true # hide password
}