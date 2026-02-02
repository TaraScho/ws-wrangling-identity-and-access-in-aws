# Deploy Bot - GitOps deployment service (ArgoCD, Spinnaker)
# Attack: iam:AttachRolePolicy allows attaching AdministratorAccess to any role
# Path: Deploy Bot → AttachRolePolicy → Attach admin policy to assumable role → AssumeRole → Admin

resource "aws_iam_policy" "iamws-deploy-bot-policy" {
  name        = "iamws-deploy-bot-policy"
  path        = "/"
  description = "Allows attaching policies to roles - vulnerable to privesc via iam:AttachRolePolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "iam:AttachRolePolicy"
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "iamws-deploy-bot-role" {
  name                = "iamws-deploy-bot-role"
  assume_role_policy  = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = var.aws_assume_role_arn
        }
      },
    ]
  })
}

resource "aws_iam_user" "iamws-deploy-bot-user" {
  name = "iamws-deploy-bot-user"
  path = "/"
}

resource "aws_iam_access_key" "iamws-deploy-bot-user" {
  user = aws_iam_user.iamws-deploy-bot-user.name
}

resource "aws_iam_user_policy_attachment" "iamws-deploy-bot-user-attach-policy" {
  user       = aws_iam_user.iamws-deploy-bot-user.name
  policy_arn = aws_iam_policy.iamws-deploy-bot-policy.arn
}

resource "aws_iam_role_policy_attachment" "iamws-deploy-bot-role-attach-policy" {
  role       = aws_iam_role.iamws-deploy-bot-role.name
  policy_arn = aws_iam_policy.iamws-deploy-bot-policy.arn
}
