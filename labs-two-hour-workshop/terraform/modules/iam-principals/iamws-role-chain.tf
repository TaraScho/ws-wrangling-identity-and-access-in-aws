# Role Chain - Cross-account deployment pipeline
# Attack: sts:AssumeRole chaining through multiple roles to reach high privileges
# Path: User → start-role → middle-role → end-role (with *:* permissions) → Admin
# Note: Each role trusts only the previous hop, requiring the full chain to escalate

resource "aws_iam_policy" "iamws-role-chain-high-priv-policy" {
  name        = "iamws-role-chain-high-priv-policy"
  path        = "/"
  description = "High privilege policy for the ending role in the chain"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "iamws-role-chain-start-role" {
  name = "iamws-role-chain-start-role"
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

resource "aws_iam_role" "iamws-role-chain-middle-role" {
  name = "iamws-role-chain-middle-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = aws_iam_role.iamws-role-chain-start-role.arn
        }
      },
    ]
  })
}

resource "aws_iam_role" "iamws-role-chain-end-role" {
  name = "iamws-role-chain-end-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = aws_iam_role.iamws-role-chain-middle-role.arn
        }
      },
    ]
  })
}

resource "aws_iam_user" "iamws-role-chain-user" {
  name = "iamws-role-chain-user"
  path = "/"
}

resource "aws_iam_access_key" "iamws-role-chain-user" {
  user = aws_iam_user.iamws-role-chain-user.name
}

resource "aws_iam_role_policy_attachment" "iamws-role-chain-end-role-attach-policy" {
  role       = aws_iam_role.iamws-role-chain-end-role.name
  policy_arn = aws_iam_policy.iamws-role-chain-high-priv-policy.arn
}
