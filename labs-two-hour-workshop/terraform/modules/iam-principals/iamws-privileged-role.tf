# ═══════════════════════════════════════════════════════════════════════════
# EXERCISE 2: Privileged Admin Role (principal-access via overly permissive trust)
# ═══════════════════════════════════════════════════════════════════════════
# Attack: Trust policy trusts account root, allowing any principal to assume
# Path: Any user with sts:AssumeRole → Assume privileged role → Full admin
# Category: principal-access (pathfinding.cloud)
# Root Cause: Trust policy uses account root notation instead of explicit principals
# Defense: Harden trust policy (Resource Policy)

# The privileged target role - has AdministratorAccess but overly permissive trust
resource "aws_iam_role" "iamws-privileged-admin-role" {
  name = "iamws-privileged-admin-role"

  # ROOT CAUSE: Trusts account root - any principal in the account with sts:AssumeRole can assume this
  # This is a common misconfiguration when "restricting" a role to "just our account"
  # The fix is to trust SPECIFIC principals, not the account root
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = var.aws_root_user }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "iamws-privileged-admin-role-admin" {
  role       = aws_iam_role.iamws-privileged-admin-role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Low-privilege user that has sts:AssumeRole permission (the attacker)
resource "aws_iam_policy" "iamws-role-assumer-policy" {
  name        = "iamws-role-assumer-policy"
  path        = "/"
  description = "Allows assuming roles - combined with permissive trust policy enables privesc"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAssumeRole"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        # NOTE: This Resource: * is NOT the root cause!
        # Even with a specific ARN here, if the trust policy is permissive, the attack works.
        # The root cause is the TRUST POLICY on the target role.
        Resource = "*"
      },
      {
        Sid    = "AllowReadOnly"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user" "iamws-role-assumer-user" {
  name = "iamws-role-assumer-user"
  path = "/"
}

resource "aws_iam_access_key" "iamws-role-assumer-user" {
  user = aws_iam_user.iamws-role-assumer-user.name
}

resource "aws_iam_user_policy_attachment" "iamws-role-assumer-user-attach" {
  user       = aws_iam_user.iamws-role-assumer-user.name
  policy_arn = aws_iam_policy.iamws-role-assumer-policy.arn
}

# Also create a role version for flexibility in the lab
resource "aws_iam_role" "iamws-role-assumer-role" {
  name = "iamws-role-assumer-role"
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

resource "aws_iam_role_policy_attachment" "iamws-role-assumer-role-attach" {
  role       = aws_iam_role.iamws-role-assumer-role.name
  policy_arn = aws_iam_policy.iamws-role-assumer-policy.arn
}
