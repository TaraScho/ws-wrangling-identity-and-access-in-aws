# Webhook Handler - Alert integration service (Slack, PagerDuty)
# Attack: iam:PassRole + lambda:CreateFunction allows creating Lambda with any role
# Path: Webhook Handler → PassRole → Create Lambda with iamws-prod-deploy-role → Invoke → Admin

resource "aws_iam_policy" "iamws-webhook-handler-policy" {
  name        = "iamws-webhook-handler-policy"
  path        = "/"
  description = "Allows Lambda creation with PassRole - vulnerable to privesc via lambda:CreateFunction + iam:PassRole"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "iam:PassRole",
          "lambda:CreateFunction",
          "lambda:InvokeFunction"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "iamws-webhook-handler-role" {
  name = "iamws-webhook-handler-role"
  assume_role_policy = jsonencode({
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

resource "aws_iam_user" "iamws-webhook-handler-user" {
  name = "iamws-webhook-handler-user"
  path = "/"
}

resource "aws_iam_access_key" "iamws-webhook-handler-user" {
  user = aws_iam_user.iamws-webhook-handler-user.name
}

resource "aws_iam_user_policy_attachment" "iamws-webhook-handler-user-attach-policy" {
  user       = aws_iam_user.iamws-webhook-handler-user.name
  policy_arn = aws_iam_policy.iamws-webhook-handler-policy.arn
}

resource "aws_iam_role_policy_attachment" "iamws-webhook-handler-role-attach-policy" {
  role       = aws_iam_role.iamws-webhook-handler-role.name
  policy_arn = aws_iam_policy.iamws-webhook-handler-policy.arn
}
