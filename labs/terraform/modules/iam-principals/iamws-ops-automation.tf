# Ops Automation - Operations maintenance scripts (patching, backups)
# Attack: ssm:SendCommand allows running commands on any EC2 instance
# Path: Ops Automation → SendCommand to EC2 with iamws-prod-deploy-role → Execute as admin role → Admin

resource "aws_iam_policy" "iamws-ops-automation-policy" {
  name        = "iamws-ops-automation-policy"
  path        = "/"
  description = "Allows SSM command execution - vulnerable to privesc via ssm:SendCommand on instances with privileged roles"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:SendCommand"
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "iamws-ops-automation-role" {
  name                = "iamws-ops-automation-role"
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

resource "aws_iam_user" "iamws-ops-automation-user" {
  name = "iamws-ops-automation-user"
  path = "/"
}

resource "aws_iam_access_key" "iamws-ops-automation-user" {
  user = aws_iam_user.iamws-ops-automation-user.name
}

resource "aws_iam_user_policy_attachment" "iamws-ops-automation-user-attach-policy" {
  user       = aws_iam_user.iamws-ops-automation-user.name
  policy_arn = aws_iam_policy.iamws-ops-automation-policy.arn
}

resource "aws_iam_role_policy_attachment" "iamws-ops-automation-role-attach-policy" {
  role       = aws_iam_role.iamws-ops-automation-role.name
  policy_arn = aws_iam_policy.iamws-ops-automation-policy.arn
}
