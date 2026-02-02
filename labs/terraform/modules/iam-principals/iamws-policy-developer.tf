# ═══════════════════════════════════════════════════════════════════════════
# EXERCISE 1: Policy Developer (self-escalation via CreatePolicyVersion)
# ═══════════════════════════════════════════════════════════════════════════
# Attack: iam:CreatePolicyVersion allows modifying a policy attached to self
# Path: Developer → CreatePolicyVersion → Add admin permissions to attached policy → Full admin
# Category: self-escalation (pathfinding.cloud)
# Root Cause: User can create new versions of a policy that's attached to them
# Defense: Permissions Boundary

# A customer-managed policy attached to the user (this is what gets modified)
resource "aws_iam_policy" "iamws-developer-tools-policy" {
  name        = "iamws-developer-tools-policy"
  path        = "/"
  description = "Developer tools policy - the target of the CreatePolicyVersion attack"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowDeveloperTools"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# The vulnerable policy - allows CreatePolicyVersion on any policy
resource "aws_iam_policy" "iamws-policy-developer-policy" {
  name        = "iamws-policy-developer-policy"
  path        = "/"
  description = "Allows managing policy versions - vulnerable to privesc via iam:CreatePolicyVersion"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPolicyVersionManagement"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicyVersion",
          "iam:ListPolicyVersions",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:SetDefaultPolicyVersion"
        ]
        # ROOT CAUSE: Can modify ANY policy, including ones attached to self
        # Even with Resource constraint, if user can modify their OWN attached policy,
        # they can escalate. The real fix is a Permissions Boundary.
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user" "iamws-policy-developer-user" {
  name = "iamws-policy-developer-user"
  path = "/"
}

resource "aws_iam_access_key" "iamws-policy-developer-user" {
  user = aws_iam_user.iamws-policy-developer-user.name
}

# Attach both policies to user - the developer tools AND the policy management
resource "aws_iam_user_policy_attachment" "iamws-policy-developer-user-tools" {
  user       = aws_iam_user.iamws-policy-developer-user.name
  policy_arn = aws_iam_policy.iamws-developer-tools-policy.arn
}

resource "aws_iam_user_policy_attachment" "iamws-policy-developer-user-mgmt" {
  user       = aws_iam_user.iamws-policy-developer-user.name
  policy_arn = aws_iam_policy.iamws-policy-developer-policy.arn
}

# Also create a role version for flexibility in the lab
resource "aws_iam_role" "iamws-policy-developer-role" {
  name = "iamws-policy-developer-role"
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

resource "aws_iam_role_policy_attachment" "iamws-policy-developer-role-tools" {
  role       = aws_iam_role.iamws-policy-developer-role.name
  policy_arn = aws_iam_policy.iamws-developer-tools-policy.arn
}

resource "aws_iam_role_policy_attachment" "iamws-policy-developer-role-mgmt" {
  role       = aws_iam_role.iamws-policy-developer-role.name
  policy_arn = aws_iam_policy.iamws-policy-developer-policy.arn
}
