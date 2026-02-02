terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

module "iam-principals" {
  source              = "./modules/iam-principals"
  aws_assume_role_arn = (var.aws_assume_role_arn != "" ? var.aws_assume_role_arn : data.aws_caller_identity.current.arn)
  aws_root_user       = format("arn:aws:iam::%s:root", data.aws_caller_identity.current.account_id)
}

module "ec2" {
  source              = "./modules/ec2"
  aws_assume_role_arn = (var.aws_assume_role_arn != "" ? var.aws_assume_role_arn : data.aws_caller_identity.current.arn)
}

module "cloudformation" {
  source                       = "./modules/cloudformation"
  aws_assume_role_arn          = (var.aws_assume_role_arn != "" ? var.aws_assume_role_arn : data.aws_caller_identity.current.arn)
  shared_high_priv_servicerole = format("arn:aws:iam::%s:role/iamws-prod-deploy-role", data.aws_caller_identity.current.account_id)
}

module "lambda" {
  source              = "./modules/lambda"
  aws_assume_role_arn = (var.aws_assume_role_arn != "" ? var.aws_assume_role_arn : data.aws_caller_identity.current.arn)
}
