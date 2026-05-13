# Lab 0 - Prerequisites: Self-Service Setup

This guide walks you through setting up the workshop environment on your own machine. After completing these steps, you'll pick up at the **Privilege Escalation Categories** section of Lab 1.

> [!IMPORTANT]
> **Never deploy lab resources in a production AWS account.** This workshop intentionally deploys vulnerable IAM resources that create serious privilege escalation paths. Use a dedicated sandbox or test account.

> [!NOTE]
> **Facilitated workshop participants:** Skip this guide entirely. Follow Lab 1, Steps 1-3 instead — the setup script handles everything for you.

---

## Prerequisites Checklist

Before you begin, make sure you have the following:

1. **AWS account** with an identity that has ReadOnlyAccess plus permissions to create: IAM users, roles, policies, and access keys; Lambda functions; EC2 security groups; S3 buckets; CloudFormation stacks; and Secrets Manager secrets.
1. **AWS CLI** installed and configured with valid credentials (`aws sts get-caller-identity` succeeds).
1. **Docker** installed and running (required for awspx).
1. **Python 3** with `venv` support (`python3 -m venv --help` succeeds).
1. **Git** installed.

---

## Tool Installation

### 1. Terraform

Terraform provisions the vulnerable lab infrastructure.

Install Terraform for your platform using the [official install guide](https://developer.hashicorp.com/terraform/install).

**Verify:**

```bash
terraform version
```

---

### 2. pmapper (Principal Mapper)

pmapper is an open-source tool that maps IAM permissions and identifies privilege escalation paths.

Install it in a Python virtual environment:

```bash
python3 -m venv ~/pmapper-venv
source ~/pmapper-venv/bin/activate
pip install --upgrade pip
pip install principalmapper
```

**Python 3.10+ compatibility fix:** pmapper uses `collections.Mapping` which was moved to `collections.abc` in Python 3.10. Apply this patch:

```bash
CASE_DICT=$(python3 -c "import principalmapper.util.case_insensitive_dict as m; print(m.__file__)")
sed -i.bak 's/from collections import Mapping, MutableMapping, OrderedDict/from collections.abc import Mapping, MutableMapping\nfrom collections import OrderedDict/' "$CASE_DICT"
```

> [!NOTE]
> On macOS, `sed -i` requires a backup extension (the `.bak` above handles this). You can delete the `.bak` file afterward.

**Verify:**

```bash
pmapper --help
```

> [!TIP]
> When you're done with the workshop, deactivate the virtual environment with `deactivate`. To use pmapper in future terminal sessions, re-activate it with `source ~/pmapper-venv/bin/activate`.

---

### 3. awspx

awspx is a graph-based tool for visualizing IAM relationships in a Neo4j-backed web UI.

**Start the awspx container:**

```bash
docker run -itd \
  --name awspx \
  --hostname=awspx \
  --env NEO4J_AUTH=neo4j/password \
  -p 80:80 \
  -p 7687:7687 \
  -p 7373:7373 \
  -p 7474:7474 \
  -e NEO4J_dbms_security_procedures_unrestricted=apoc.jar \
  beatro0t/awspx:latest
```

> [!NOTE]
> If port 80 is already in use on your machine, change `-p 80:80` to another port (e.g., `-p 8080:80`) and use `http://localhost:8080` instead of `http://localhost` throughout the labs.

**Create the awspx credential wrapper script:**

awspx runs inside Docker and needs AWS credentials passed in via environment variables. Create a wrapper script:

```bash
cat > ~/awspx-wrapper.sh << 'EOF'
#!/bin/bash
# Wrapper for awspx: passes AWS credentials into the container

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] && [ -f ~/.aws/credentials ]; then
  export AWS_ACCESS_KEY_ID=$(grep -A2 "\[default\]" ~/.aws/credentials 2>/dev/null | grep aws_access_key_id | cut -d'=' -f2 | tr -d ' ')
  export AWS_SECRET_ACCESS_KEY=$(grep -A2 "\[default\]" ~/.aws/credentials 2>/dev/null | grep aws_secret_access_key | cut -d'=' -f2 | tr -d ' ')
  SESSION_TOKEN=$(grep -A3 "\[default\]" ~/.aws/credentials 2>/dev/null | grep aws_session_token | cut -d'=' -f2 | tr -d ' ')
  if [ -n "$SESSION_TOKEN" ]; then
    export AWS_SESSION_TOKEN="$SESSION_TOKEN"
    export AWS_SECURITY_TOKEN="$SESSION_TOKEN"
  fi
fi

docker exec -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
  ${AWS_SESSION_TOKEN:+-e AWS_SESSION_TOKEN} \
  ${AWS_SECURITY_TOKEN:+-e AWS_SECURITY_TOKEN} \
  awspx awspx "$@"
EOF
chmod +x ~/awspx-wrapper.sh
```

**Verify:**

Navigate to [http://localhost](http://localhost) in your browser. You should see the awspx web interface. It may take 30-60 seconds for Neo4j to start up inside the container.

---

### 4. SSM Session Manager Plugin

The SSM Session Manager Plugin is required for connecting to the workshop EC2 instance.

Install it for your platform using the [official AWS install guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).

**Verify:**

```bash
session-manager-plugin --version
```

---

## Deploy Lab Infrastructure

Clone the workshop repository and deploy the vulnerable infrastructure with Terraform:

```bash
git clone https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws.git ~/workshop
cd ~/workshop
```

```bash
terraform -chdir=labs/terraform init -input=false
terraform -chdir=labs/terraform apply -auto-approve -input=false
```

This creates 6 IAM users with intentionally misconfigured permissions, plus supporting Lambda functions, EC2 security groups, S3 buckets, and other resources.

---

## Configure Exercise AWS CLI Profiles

Terraform creates 6 exercise users, each with access keys exposed as Terraform outputs. Configure an AWS CLI profile for each one so you can easily switch between them during the exercises.

Run the following script from the repository root:

```bash
PROFILES=(
  "iamws-group-admin-user:group_admin"
  "iamws-policy-developer-user:policy_developer"
  "iamws-role-assumer-user:role_assumer"
  "iamws-ci-runner-user:ci_runner"
  "iamws-lambda-developer-user:lambda_developer"
  "iamws-secrets-reader-user:secrets_reader"
)

for entry in "${PROFILES[@]}"; do
  profile_name="${entry%%:*}"
  tf_prefix="${entry##*:}"

  aws configure set aws_access_key_id \
    "$(terraform -chdir=labs/terraform output -raw ${tf_prefix}_access_key_id)" \
    --profile "$profile_name"
  aws configure set aws_secret_access_key \
    "$(terraform -chdir=labs/terraform output -raw ${tf_prefix}_secret_access_key)" \
    --profile "$profile_name"
  aws configure set region us-east-1 --profile "$profile_name"

  echo "Configured profile: $profile_name"
done
```

**Verify:**

```bash
aws sts get-caller-identity --profile iamws-policy-developer-user
```

You should see output containing `iamws-policy-developer-user` in the ARN.

---

## Validation Checklist

Run through these checks to confirm everything is ready:

```bash
# Tools installed
terraform version
pmapper --help
session-manager-plugin --version

# awspx running
curl -s -o /dev/null -w "%{http_code}" http://localhost  # Should return 200

# Exercise profiles configured (should return 6)
aws configure list-profiles | grep -c iamws

# Test an exercise profile
aws sts get-caller-identity --profile iamws-policy-developer-user
```

If all checks pass, you're ready to start Lab 1 at the **Privilege Escalation Categories** section.

---

## Cleanup

When you're done with the workshop, tear down the lab infrastructure and remove the Docker container:

```bash
terraform -chdir=labs/terraform destroy -auto-approve
docker stop awspx && docker rm awspx
```
