terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
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

resource "time_sleep" "iam_propagation" {
  depends_on      = [module.iam-principals]
  create_duration = "15s"
}

module "cloudformation" {
  source                       = "./modules/cloudformation"
  aws_assume_role_arn          = (var.aws_assume_role_arn != "" ? var.aws_assume_role_arn : data.aws_caller_identity.current.arn)
  shared_high_priv_servicerole = module.iam-principals.prod_deploy_role_arn

  depends_on = [time_sleep.iam_propagation]
}

module "lambda" {
  source              = "./modules/lambda"
  aws_assume_role_arn = (var.aws_assume_role_arn != "" ? var.aws_assume_role_arn : data.aws_caller_identity.current.arn)
}

module "s3" {
  source         = "./modules/s3"
  aws_account_id = data.aws_caller_identity.current.account_id
}
