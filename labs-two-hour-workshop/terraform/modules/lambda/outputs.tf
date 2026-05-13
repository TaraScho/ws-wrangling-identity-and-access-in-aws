# Exercise user access keys — used by setup script to create AWS CLI profiles

output "lambda_developer_access_key_id" {
  description = "Access key ID for iamws-lambda-developer-user"
  value       = aws_iam_access_key.iamws-lambda-developer-user.id
}

output "lambda_developer_secret_access_key" {
  description = "Secret access key for iamws-lambda-developer-user"
  value       = aws_iam_access_key.iamws-lambda-developer-user.secret
  sensitive   = true
}

output "secrets_reader_access_key_id" {
  description = "Access key ID for iamws-secrets-reader-user"
  value       = aws_iam_access_key.iamws-secrets-reader-user.id
}

output "secrets_reader_secret_access_key" {
  description = "Secret access key for iamws-secrets-reader-user"
  value       = aws_iam_access_key.iamws-secrets-reader-user.secret
  sensitive   = true
}
