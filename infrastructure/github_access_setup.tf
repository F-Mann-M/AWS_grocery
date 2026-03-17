### GITHUB ACTIONS OIDC SETUP AND SECURITY GROUP PERMISSIONS TO CHANGE IP IN EC2SECURITY GROUP ###

# to access AWS resources securely from GitHub Actions without using long-lived credentials, 
# set up OpenID Connect (OIDC) trust between GitHub and AWS IAM. 
# This allows GitHub to assume an IAM Role with specific permissions when running workflows.
# https://github.com/aws-actions/configure-aws-credentials

# Create an OIDC provider for GitHub in AWS IAM
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # This is GitHub's official certificate thumbprint
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"] 
}

# Create an IAM Role that GitHub can assume via OIDC
resource "aws_iam_role" "github_actions_role" {
  name = "grocerymate-github-actions-role"

  # The Trust Policy: Only allow YOUR specific repository to use this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # specify your GitHub repo here: "repo:owner/repo:*" to allow all workflows in that repo.
            "token.actions.githubusercontent.com:sub" = "repo:${var.GIT_USERNAME}/AWS_grocery:*"
          }
        }
      }
    ]
  })
}

# Give the Role permissions (e.g., ECR access to push the Docker image)
resource "aws_iam_role_policy_attachment" "github_ecr_access" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}


### SECURITY GROUP UPDATE PERMISSIONS FOR GITHUB ACTIONS ###

# Create a policy allowing GitHub to modify the Security Group
# This is necessary for the workflow to update the EC2 Security Group with the correct IP for SSH access during deployment
# instead of except all IPs, we can let GitHub Actions update the SG dynamically with the correct IP during deployment, which is more secure than allowing all IPs permanently.

resource "aws_iam_policy" "github_sg_policy" {
  name        = "grocerymate-github-sg-policy"
  description = "Allow GitHub Actions to update EC2 Security Group for SSH"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = aws_security_group.ec2_sg.arn, # allow GitHub to modify the EC2 Security Group
      }
    ]
  })
}

# Attach the new policy to your existing GitHub Actions Role
resource "aws_iam_role_policy_attachment" "github_sg_access" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.github_sg_policy.arn
}


### OUTPUTS ###

# output the Role ARN for GitHub secrets configuration
output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_role.arn
}

# Output the Security Group ID for GitHub secrets configuration
output "ec2_security_group_id" {
  value = aws_security_group.ec2_sg.id # Replace 'ec2_sg' with the actual name of your EC2 Security Group resource!
}