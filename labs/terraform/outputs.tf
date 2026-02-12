# Exercise user access keys — passed through from modules for setup script

# iam-principals module outputs

output "group_admin_access_key_id" {
  value     = module.iam-principals.group_admin_access_key_id
}

output "group_admin_secret_access_key" {
  value     = module.iam-principals.group_admin_secret_access_key
  sensitive = true
}

output "policy_developer_access_key_id" {
  value     = module.iam-principals.policy_developer_access_key_id
}

output "policy_developer_secret_access_key" {
  value     = module.iam-principals.policy_developer_secret_access_key
  sensitive = true
}

output "role_assumer_access_key_id" {
  value     = module.iam-principals.role_assumer_access_key_id
}

output "role_assumer_secret_access_key" {
  value     = module.iam-principals.role_assumer_secret_access_key
  sensitive = true
}

output "ci_runner_access_key_id" {
  value     = module.iam-principals.ci_runner_access_key_id
}

output "ci_runner_secret_access_key" {
  value     = module.iam-principals.ci_runner_secret_access_key
  sensitive = true
}

# lambda module outputs

output "lambda_developer_access_key_id" {
  value     = module.lambda.lambda_developer_access_key_id
}

output "lambda_developer_secret_access_key" {
  value     = module.lambda.lambda_developer_secret_access_key
  sensitive = true
}

output "secrets_reader_access_key_id" {
  value     = module.lambda.secrets_reader_access_key_id
}

output "secrets_reader_secret_access_key" {
  value     = module.lambda.secrets_reader_secret_access_key
  sensitive = true
}
