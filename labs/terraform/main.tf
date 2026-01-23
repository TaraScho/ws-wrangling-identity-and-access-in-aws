terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region                  = "us-east-1"    
  #shared_credentials_file = var.aws_local_creds_file
  #profile                 = var.aws_local_profile
}

data "aws_caller_identity" "current" {}

module "privesc-paths" {
  source = "./modules/free-resources/privesc-paths"
  aws_assume_role_arn = (var.aws_assume_role_arn != "" ? var.aws_assume_role_arn : data.aws_caller_identity.current.arn)
  aws_root_user = format("arn:aws:iam::%s:root", data.aws_caller_identity.current.account_id)
}

###################
# Module: Tool Testing
# DISABLED: Not needed for workshop labs
###################

#module "tool-testing" {
#  source = "./modules/free-resources/tool-testing"
#  aws_assume_role_arn = (var.aws_assume_role_arn != "" ? var.aws_assume_role_arn : data.aws_caller_identity.current.arn)
#  aws_root_user = format("arn:aws:iam::%s:root", data.aws_caller_identity.current.account_id)
#}

###################
# Module: Lambda
# ENABLED FOR WORKSHOP: PassRole + Lambda attacks
###################

module "lambda" {
  source = "./modules/non-free-resources/lambda"
  aws_assume_role_arn = (var.aws_assume_role_arn != "" ? var.aws_assume_role_arn : data.aws_caller_identity.current.arn)
}

###################
# Module: EC2
# ENABLED FOR WORKSHOP: PassRole + EC2 attacks (privesc3)
###################

module "ec2" {
  source = "./modules/non-free-resources/ec2"
  aws_assume_role_arn = (var.aws_assume_role_arn != "" ? var.aws_assume_role_arn : data.aws_caller_identity.current.arn)
}

 
###################
# Module: Glue
# DISABLED FOR WORKSHOP: Glue dev endpoints have hourly charges
# Uncomment if you want to explore Glue-based privilege escalation
###################

#module "glue" {
#   source = "./modules/non-free-resources/glue"
#   aws_assume_role_arn = (var.aws_assume_role_arn != "" ? var.aws_assume_role_arn : data.aws_caller_identity.current.arn)
#}

###################
# Module: SageMaker
# DISABLED FOR WORKSHOP: SageMaker notebooks have hourly charges
# Uncomment if you want to explore SageMaker-based privilege escalation
###################

#module "sagemaker" {
#   source = "./modules/non-free-resources/sagemaker"
#   aws_assume_role_arn = (var.aws_assume_role_arn != "" ? var.aws_assume_role_arn : data.aws_caller_identity.current.arn)
#}

###################
# Module: CloudFormation
# ENABLED FOR WORKSHOP: PassRole + CloudFormation attacks
###################

module "cloudformation" {
  source = "./modules/non-free-resources/cloudformation"
  aws_assume_role_arn = (var.aws_assume_role_arn != "" ? var.aws_assume_role_arn : data.aws_caller_identity.current.arn)
  shared_high_priv_servicerole = format("arn:aws:iam::%s:role/privesc-high-priv-service-role", data.aws_caller_identity.current.account_id)
}

