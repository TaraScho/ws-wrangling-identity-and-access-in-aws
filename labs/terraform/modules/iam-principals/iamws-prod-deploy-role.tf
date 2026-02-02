# ═══════════════════════════════════════════════════════════════════════════
# THE TARGET: Production Deployment Role
# ═══════════════════════════════════════════════════════════════════════════
# This is the "crown jewel" role that all attack scenarios aim to reach.
# Has *:* permissions and can be assumed by multiple AWS services.
# In a real environment, this would be the deployment role for production infrastructure.

resource "aws_iam_policy" "iamws-prod-deploy-policy" {
  name        = "iamws-prod-deploy-policy"
  path        = "/"
  description = "High privilege policy for production deployments"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "*"
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

data "aws_iam_policy" "AmazonSSMManagedInstanceCore" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role" "iamws-prod-deploy-role" {
  name                = "iamws-prod-deploy-role"
  assume_role_policy  = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = [
            "ec2.amazonaws.com",
            "datapipeline.amazonaws.com",
            "cloudformation.amazonaws.com",
            "lambda.amazonaws.com",
            "glue.amazonaws.com",
            "ecs-tasks.amazonaws.com",
            "codebuild.amazonaws.com",
            "eks.amazonaws.com",
            "sagemaker.amazonaws.com",
            "elasticbeanstalk.amazonaws.com"
          ]
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "iamws-prod-deploy-profile" {
 name = "iamws-prod-deploy-profile"
 role = aws_iam_role.iamws-prod-deploy-role.name
}

resource "aws_iam_role_policy_attachment" "iamws-prod-deploy-role-attach-policy1" {
  role       = aws_iam_role.iamws-prod-deploy-role.name
  policy_arn = aws_iam_policy.iamws-prod-deploy-policy.arn
}

resource "aws_iam_role_policy_attachment" "iamws-prod-deploy-role-attach-policy2" {
  role       = aws_iam_role.iamws-prod-deploy-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
