# ═══════════════════════════════════════════════════════════════════════════
# EXERCISE 7: Group Admin (self-escalation via PutGroupPolicy)
# ═══════════════════════════════════════════════════════════════════════════
# Attack: iam:PutGroupPolicy allows writing arbitrary inline policies on any group
# Path: Group Admin → PutGroupPolicy on own group → Add *:* inline policy → Admin
# Category: self-escalation (pathfinding.cloud)
# Root Cause: PutGroupPolicy with Resource: "*" (no group ARN constraint)
# Defense: Restrict PutGroupPolicy resource to specific group ARNs

# ─────────────────────────────────────────────────────────────────────────
# IAM Groups (makes pmapper show groups in scan summary)
# ─────────────────────────────────────────────────────────────────────────

resource "aws_iam_group" "iamws-dev-team" {
  name = "iamws-dev-team"
  path = "/"
}

resource "aws_iam_group_policy" "iamws-dev-team-readonly" {
  name  = "iamws-dev-team-readonly"
  group = aws_iam_group.iamws-dev-team.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowReadOnly"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_group" "iamws-platform-team" {
  name = "iamws-platform-team"
  path = "/"
}

resource "aws_iam_group_policy" "iamws-platform-team-readonly" {
  name  = "iamws-platform-team-readonly"
  group = aws_iam_group.iamws-platform-team.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMonitoringReadOnly"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics",
          "logs:DescribeLogGroups",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────
# Group Memberships
# ─────────────────────────────────────────────────────────────────────────

resource "aws_iam_group_membership" "iamws-dev-team-members" {
  name  = "iamws-dev-team-membership"
  group = aws_iam_group.iamws-dev-team.name

  users = [
    aws_iam_user.iamws-group-admin-user.name,
  ]
}

resource "aws_iam_group_membership" "iamws-platform-team-members" {
  name  = "iamws-platform-team-membership"
  group = aws_iam_group.iamws-platform-team.name

  users = [
    aws_iam_user.iamws-ci-runner-user.name,
    aws_iam_user.iamws-ops-automation-user.name,
  ]
}

# ─────────────────────────────────────────────────────────────────────────
# Attacker principal: iamws-group-admin-user
# ─────────────────────────────────────────────────────────────────────────

# The vulnerable policy - allows PutGroupPolicy on any group
resource "aws_iam_policy" "iamws-group-admin-policy" {
  name        = "iamws-group-admin-policy"
  path        = "/"
  description = "Group admin permissions - vulnerable due to PutGroupPolicy with Resource: *"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowPutGroupPolicy"
        Effect   = "Allow"
        Action   = "iam:PutGroupPolicy"
        Resource = "*"
        # ═══════════════════════════════════════════════════════════════════
        # ROOT CAUSE: Resource: "*" means this user can write inline
        # policies on ANY group, including their own group (iamws-dev-team).
        # Since the user is a member of that group, any inline policy they
        # write immediately applies to themselves.
        #
        # THE FIX: Restrict Resource to only the groups they should manage:
        # "Resource": "arn:aws:iam::*:group/other-team"
        #
        # Even better, use a Permissions Boundary for defense-in-depth.
        # ═══════════════════════════════════════════════════════════════════
      },
      {
        Sid    = "AllowGroupEnumeration"
        Effect = "Allow"
        Action = [
          "iam:ListGroups",
          "iam:ListGroupPolicies",
          "iam:GetGroupPolicy",
          "iam:ListGroupsForUser",
          "iam:GetGroup"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user" "iamws-group-admin-user" {
  name = "iamws-group-admin-user"
  path = "/"
}

resource "aws_iam_access_key" "iamws-group-admin-user" {
  user = aws_iam_user.iamws-group-admin-user.name
}

resource "aws_iam_user_policy_attachment" "iamws-group-admin-user-attach-policy" {
  user       = aws_iam_user.iamws-group-admin-user.name
  policy_arn = aws_iam_policy.iamws-group-admin-policy.arn
}

resource "aws_iam_role" "iamws-group-admin-role" {
  name = "iamws-group-admin-role"
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

resource "aws_iam_role_policy_attachment" "iamws-group-admin-role-attach-policy" {
  role       = aws_iam_role.iamws-group-admin-role.name
  policy_arn = aws_iam_policy.iamws-group-admin-policy.arn
}
