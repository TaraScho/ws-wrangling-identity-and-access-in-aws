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
