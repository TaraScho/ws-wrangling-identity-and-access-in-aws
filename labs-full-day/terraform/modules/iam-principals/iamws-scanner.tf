# Least-privilege read-only identity used by iam-recon to scan the lab account.
# Attached: AWS-managed SecurityAudit (iam:Get*/iam:List*, sts:GetCallerIdentity,
# plus the service-side read access iam-recon's 9 edge checkers need).

resource "aws_iam_user" "iamws-scanner-user" {
  name = "iamws-scanner-user"
  path = "/"
}

resource "aws_iam_access_key" "iamws-scanner-user" {
  user = aws_iam_user.iamws-scanner-user.name
}

resource "aws_iam_user_policy_attachment" "iamws-scanner-user-securityaudit" {
  user       = aws_iam_user.iamws-scanner-user.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}
