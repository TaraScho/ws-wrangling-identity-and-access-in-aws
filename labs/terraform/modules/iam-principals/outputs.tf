# Outputs for shared resources that other modules depend on

output "prod_deploy_role_arn" {
  description = "ARN of the production deployment role for CloudFormation and other services"
  value       = aws_iam_role.iamws-prod-deploy-role.arn

  # Ensure the policy attachments complete before other modules use this role
  depends_on = [
    aws_iam_role_policy_attachment.iamws-prod-deploy-role-attach-policy1,
    aws_iam_role_policy_attachment.iamws-prod-deploy-role-attach-policy2
  ]
}

# Exercise user access keys — used by setup script to create AWS CLI profiles

output "group_admin_access_key_id" {
  description = "Access key ID for iamws-group-admin-user"
  value       = aws_iam_access_key.iamws-group-admin-user.id
}

output "group_admin_secret_access_key" {
  description = "Secret access key for iamws-group-admin-user"
  value       = aws_iam_access_key.iamws-group-admin-user.secret
  sensitive   = true
}

output "policy_developer_access_key_id" {
  description = "Access key ID for iamws-policy-developer-user"
  value       = aws_iam_access_key.iamws-policy-developer-user.id
}

output "policy_developer_secret_access_key" {
  description = "Secret access key for iamws-policy-developer-user"
  value       = aws_iam_access_key.iamws-policy-developer-user.secret
  sensitive   = true
}

output "role_assumer_access_key_id" {
  description = "Access key ID for iamws-role-assumer-user"
  value       = aws_iam_access_key.iamws-role-assumer-user.id
}

output "role_assumer_secret_access_key" {
  description = "Secret access key for iamws-role-assumer-user"
  value       = aws_iam_access_key.iamws-role-assumer-user.secret
  sensitive   = true
}

output "ci_runner_access_key_id" {
  description = "Access key ID for iamws-ci-runner-user"
  value       = aws_iam_access_key.iamws-ci-runner-user.id
}

output "ci_runner_secret_access_key" {
  description = "Secret access key for iamws-ci-runner-user"
  value       = aws_iam_access_key.iamws-ci-runner-user.secret
  sensitive   = true
}
