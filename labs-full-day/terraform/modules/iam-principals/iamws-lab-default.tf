# Persistent admin identity used by the setup script to populate ~/.aws/credentials.
#
# Two things rely on this user:
#   1. ~/.aws/credentials [default] is set to its access key, so the AWS CLI
#      keeps working after a Guacamole session disconnect drops the env-var
#      credentials the learner started with.
#   2. ~/.aws/credentials [iamws-lab-default] is also set to its access key, so
#      lab docs that reference `--profile iamws-lab-default` resolve.
#
# Managing this in Terraform (instead of imperatively in the setup script)
# avoids IAM rate-limit throttling on fresh accounts and lets `terraform destroy`
# clean it up automatically.

resource "aws_iam_user" "iamws-lab-default-user" {
  name = "iamws-lab-default"
  path = "/"
}

resource "aws_iam_access_key" "iamws-lab-default-user" {
  user = aws_iam_user.iamws-lab-default-user.name
}

resource "aws_iam_user_policy_attachment" "iamws-lab-default-user-admin" {
  user       = aws_iam_user.iamws-lab-default-user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
