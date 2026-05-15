resource "aws_cloudformation_stack" "iamws-demo-stack" {
  name         = "iamws-demo-stack"
  iam_role_arn = var.shared_high_priv_servicerole

  template_body = <<STACK
{
  "Resources" : {
    "Secret1" : {
      "Type" : "AWS::SecretsManager::Secret",
      "Properties" : {
          "Description" : "Super strong password that nobody would ever be able to guess",
          "SecretString" : "Summer2021!"
      }
    }
  }
}
STACK
}
