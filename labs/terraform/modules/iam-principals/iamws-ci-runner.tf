# ═══════════════════════════════════════════════════════════════════════════
# EXERCISE 3: CI Runner (new-passrole via missing iam:PassedToService condition)
# ═══════════════════════════════════════════════════════════════════════════
# Attack: iam:PassRole + ec2:RunInstances allows launching EC2 with any role
# Path: CI Runner → PassRole → Launch EC2 with iamws-prod-deploy-role → SSH/SSM → Admin
# Category: new-passrole (pathfinding.cloud)
# Root Cause: PassRole has no iam:PassedToService condition key
# Defense: Add iam:PassedToService condition to restrict which services can receive the role

resource "aws_iam_policy" "iamws-ci-runner-policy" {
  name        = "iamws-ci-runner-policy"
  path        = "/"
  description = "CI runner permissions - vulnerable due to missing iam:PassedToService condition"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = "*"
        # ═══════════════════════════════════════════════════════════════════
        # ROOT CAUSE: Missing condition block!
        # Without iam:PassedToService, this role can be passed to ANY service.
        # The attacker can pass a privileged role to EC2 and harvest its credentials.
        #
        # THE FIX: Add this condition to restrict PassRole to specific services:
        # "Condition": {
        #   "StringEquals": {
        #     "iam:PassedToService": "ec2.amazonaws.com"
        #   }
        # }
        #
        # Even better, combine with a Resource constraint for defense-in-depth.
        # ═══════════════════════════════════════════════════════════════════
      },
      {
        Sid    = "AllowEC2Operations"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeKeyPairs",
          "ec2:CreateKeyPair",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowSSMConnect"
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:TerminateSession",
          "ssm:DescribeSessions"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "iamws-ci-runner-role" {
  name = "iamws-ci-runner-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { AWS = var.aws_assume_role_arn }
      }
    ]
  })
}

resource "aws_iam_user" "iamws-ci-runner-user" {
  name = "iamws-ci-runner-user"
  path = "/"
}

resource "aws_iam_access_key" "iamws-ci-runner-user" {
  user = aws_iam_user.iamws-ci-runner-user.name
}

resource "aws_iam_user_policy_attachment" "iamws-ci-runner-user-attach-policy" {
  user       = aws_iam_user.iamws-ci-runner-user.name
  policy_arn = aws_iam_policy.iamws-ci-runner-policy.arn
}

resource "aws_iam_role_policy_attachment" "iamws-ci-runner-role-attach-policy" {
  role       = aws_iam_role.iamws-ci-runner-role.name
  policy_arn = aws_iam_policy.iamws-ci-runner-policy.arn
}
