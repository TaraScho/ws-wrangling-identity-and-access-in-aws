git clone https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws.git
cd ws-wrangling-identity-and-access-in-aws

export AWS_DEFAULT_REGION=us-west-2
export AWS_SECRET_ACCESS

cd labs/terraform
terraform init
terraform apply --auto-approve