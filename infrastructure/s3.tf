resource "aws_s3_bucket" "avatars" {
  bucket = "grocerymate-avatars-friedemann"

  tags = {
    Name        = "grocerymate-avatars"
    Environment = "Dev"
  }
}