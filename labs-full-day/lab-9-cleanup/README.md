# Full-Day Workshop — Lab Cleanup

End-to-end teardown for everything the full-day workshop creates: scenario exercise artifacts, the Kiro hardening lab CloudFormation stacks, the Terraform-deployed vulnerable infrastructure, and the AWS CLI profiles. Run this when you're done with the workshop and want your sandbox account empty.

## Before you begin

1. Run every step as the **`iamws-lab-default`** admin profile that `bsides-setup.sh` configured for you (NOT one of the scenario users). Examples in this doc use `--profile iamws-lab-default` throughout.

1. Set your account ID once:

    ```bash
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile iamws-lab-default)
    ```

1. Cleanup is sequenced deliberately: out-of-band artifacts created during the scenarios block `terraform destroy` if left in place (the running EC2 instance pins its instance profile, the extra policy version pins its IAM policy, etc.). Don't skip ahead to `terraform destroy`.

---

## Step 1: Revert scenario artifacts

Each scenario's exploit and defense steps create resources or modify state outside of Terraform. Clear these first so `terraform destroy` has a clean run.

### Scenario 1a — CreatePolicyVersion

If you ran the exploit (created v2 of `iamws-developer-tools-policy` and set it as default), reset it. Terraform can't delete a customer-managed policy that still has a non-default version attached.

```bash
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/iamws-developer-tools-policy"

aws iam set-default-policy-version \
  --policy-arn $POLICY_ARN --version-id v1 --profile iamws-lab-default 2>/dev/null || true

aws iam delete-policy-version \
  --policy-arn $POLICY_ARN --version-id v2 --profile iamws-lab-default 2>/dev/null || true
```

### Scenario 2 — Trust Policy `:root`

The defense step (Part D) already restored a specific-principal trust policy. Terraform will revert the role to its original `:root` trust policy on destroy — no manual cleanup needed.

### Scenario 3 — PassRole + EC2

Terminate the EC2 instance launched during the attack (it pins `iamws-prod-deploy-profile`, blocking instance profile deletion in `terraform destroy`):

```bash
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters \
    "Name=iam-instance-profile.arn,Values=arn:aws:iam::*:instance-profile/iamws-prod-deploy-profile" \
    "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text \
  --profile iamws-lab-default)

if [ -n "$INSTANCE_IDS" ]; then
  aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --profile iamws-lab-default
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS --profile iamws-lab-default
fi
```

Remove the inline defense policy from `iamws-ci-runner-user` (inline policies block IAM user deletion):

```bash
aws iam delete-user-policy \
  --user-name iamws-ci-runner-user --policy-name SecurePassRole \
  --profile iamws-lab-default 2>/dev/null || true
```

### Scenario 4 — Lambda UpdateFunctionCode

The hijacked Lambda code on `iamws-privileged-lambda` will be deleted with the function itself in `terraform destroy` — no need to restore it first.

Remove the inline defense policy from `iamws-lambda-developer-user`:

```bash
aws iam delete-user-policy \
  --user-name iamws-lambda-developer-user --policy-name SecureLambdaDeveloper \
  --profile iamws-lab-default 2>/dev/null || true
```

Remove the local exploit artifacts:

```bash
rm -rf /tmp/iamws-exploit /tmp/dummy_lambda.py /tmp/dummy_lambda.zip
```

### Scenario 5 — Lambda Secrets

Remove the inline role policy added during the defense (otherwise the IAM role can't be deleted):

```bash
aws iam delete-role-policy \
  --role-name iamws-app-lambda-role --policy-name SecretsManagerAccess \
  --profile iamws-lab-default 2>/dev/null || true
```

Delete the Secrets Manager secret created during the defense:

```bash
aws secretsmanager delete-secret \
  --secret-id iamws-app-secrets \
  --force-delete-without-recovery \
  --profile iamws-lab-default 2>/dev/null || true
```

The Lambda's environment variables will be reset (or the function deleted) by `terraform destroy`.

### Permissions boundaries / condition keys exercise

If you ran [Lab 4: Permissions Boundaries & Condition Keys](../lab-4-permissions-boundaries-and-condition-keys/README.md), remove the boundary and the policy it references (a user with an attached permissions boundary cannot be deleted, and the managed policy itself was created out of band):

```bash
aws iam delete-user-permissions-boundary \
  --user-name iamws-policy-developer-user \
  --profile iamws-lab-default 2>/dev/null || true

aws iam delete-policy \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/DeveloperBoundary \
  --profile iamws-lab-default 2>/dev/null || true

rm -f /tmp/boundary-policy.json
```

---

## Step 2: Tear down the Kiro IAM Hardening lab (if you ran it)

The Kiro lab deploys three CloudFormation stacks and an S3 analytics bucket independently of Terraform. Skip this step if you did not run the Kiro lab.

```bash
aws s3 rm "s3://analytics-data-${ACCOUNT_ID}" --recursive \
  --profile iamws-lab-default 2>/dev/null || true

for stack in IAM-Hardening-Lab-Secure IAM-Hardening-Lab-Insecure IAM-Hardening-Lab-Bucket; do
  aws cloudformation delete-stack --stack-name "$stack" --profile iamws-lab-default 2>/dev/null || true
done

for stack in IAM-Hardening-Lab-Secure IAM-Hardening-Lab-Insecure IAM-Hardening-Lab-Bucket; do
  aws cloudformation wait stack-delete-complete --stack-name "$stack" --profile iamws-lab-default 2>/dev/null || true
done
```

> [!WARNING]
> If a stack deletion fails, the most common causes are:
>
> - An EC2 instance still using one of the lab's instance profiles — terminate it (Step 1, Scenario 3 handles the workshop's instance, but if you launched extras for the easter-egg exercise, terminate those too) and retry.
> - The analytics bucket isn't empty — re-run the `aws s3 rm ... --recursive` line and retry the stack delete.

---

## Step 3: Destroy the Terraform-deployed infrastructure

```bash
TERRAFORM_DIR="$(git rev-parse --show-toplevel)/labs-two-hour-workshop/terraform"

# Workshop VMs ship with either Terraform or OpenTofu — pick whichever is present.
TF_BIN=$(command -v terraform || command -v tofu) \
  || { echo "Need terraform or tofu installed"; exit 1; }

"$TF_BIN" -chdir="$TERRAFORM_DIR" destroy -auto-approve
```

This removes all eight workshop IAM users (six scenario users, `iamws-scanner-user`, and `iamws-lab-default`), their policies and groups, the privileged roles, the crown jewels S3 bucket, the privileged and app Lambdas, and the EC2 security group / VPC bits the workshop provisioned.

> [!IMPORTANT]
> `iamws-lab-default` is the profile you used to run every step above. Once `terraform destroy` finishes, that IAM user is gone — any further `--profile iamws-lab-default` calls will fail with `InvalidClientTokenId`. The remaining cleanup step only edits local files and doesn't need an AWS identity.

If `terraform destroy` errors out, the most likely cause is a Step 1 artifact left behind — re-check Scenario 3 (running EC2 instance) and Scenario 1a (non-default policy version), fix, and re-run.

---

## Step 4: Remove the local AWS CLI profiles

Setup wrote credentials for eight workshop profiles into `~/.aws/credentials` and `~/.aws/config` (the six scenario profiles, `iamws-scanner-user`, and `iamws-lab-default`). It also mirrored the `iamws-lab-default` credentials into the unnamed `default` profile. Remove them all so you don't leave stale (and now-invalid) access keys sitting in the file:

```bash
for profile in \
    default \
    iamws-scanner-user \
    iamws-group-admin-user \
    iamws-policy-developer-user \
    iamws-role-assumer-user \
    iamws-ci-runner-user \
    iamws-lambda-developer-user \
    iamws-secrets-reader-user \
    iamws-lab-default ; do
  aws configure --profile "$profile" set aws_access_key_id "" 2>/dev/null
  aws configure --profile "$profile" set aws_secret_access_key "" 2>/dev/null
done
```

> [!NOTE]
> `aws configure set` with an empty value leaves the `[profile ...]` headers in place but blanks the credentials. If you'd rather wipe them completely, open `~/.aws/credentials` and `~/.aws/config` and delete the `default` and `iamws-*` blocks by hand.

---

## Step 5 (optional): Workstation cleanup

This step is for **own-laptop** runs only. **If you used the pre-built workshop image, skip ahead to [Verify a clean account](#verify-a-clean-account)** — the simplest cleanup is to nuke the entire VM. The "Stop / cleanup" section of the [Securing the Cloud — Workstation Image](https://docs.google.com/document/d/1bLbSTfht3QR-hxu03v33n1x-NdZ5XBlaXHqSjfx8-gY/edit?usp=sharing) guide has the exact commands for VirtualBox, Tart, or Docker.

The rest of this step is for laptop runs that want to uninstall what the setup script added.

At a high level, `bsides-setup.sh` may have touched the following on your workstation:

1. **Workshop tools directory.** The script downloaded `iam-recon`, `terraform`, and (on macOS) `session-manager-plugin` into `<repo-root>/tools/bin/`. Delete the directory:

    ```bash
    rm -rf "$(git rev-parse --show-toplevel)/tools"
    ```

1. **Shell PATH and AWS defaults.** The script appended a `# Workshop tools` block to `~/.bashrc` and `~/.profile` that adds `<repo>/tools/bin` to `PATH` and sets `AWS_DEFAULT_REGION` / `AWS_PAGER`. Open each file and remove the block.

1. **System-installed SSM Session Manager plugin** (Linux only). On Linux the script installed `session-manager-plugin` as a system package via `yum` or `dpkg`. Uninstall it with the matching package manager command (`sudo yum remove session-manager-plugin` or `sudo dpkg -r session-manager-plugin`) if you don't want it sticking around.

1. **iam-recon cache.** Every iam-recon scan cached API responses under `~/.local/share/iam-recon/<account-id>/`. Remove the directory if you don't want the cached graph data on disk:

    ```bash
    rm -rf ~/.local/share/iam-recon
    ```

1. **Cloned workshop repo.** `git clone ... ~/workshop` was the suggested clone path in setup. Delete the clone wherever you put it.

The base CLI tools the script checked for at the start (`git`, `python3`, `unzip`, `curl`, `jq`, `zip`, `aws`) were not installed by the script — they were prerequisites — so leave those alone.

---

## Verify a clean account

A sanity check that nothing workshop-related is left in the sandbox account:

```bash
# No iamws-* IAM users
aws iam list-users --query 'Users[?starts_with(UserName, `iamws`)].UserName' --output text

# No iamws-* IAM roles
aws iam list-roles --query 'Roles[?starts_with(RoleName, `iamws`)].RoleName' --output text

# No iamws-* customer-managed policies
aws iam list-policies --scope Local \
  --query 'Policies[?starts_with(PolicyName, `iamws`) || PolicyName==`DeveloperBoundary`].PolicyName' \
  --output text

# No iamws-* Lambdas
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `iamws`)].FunctionName' --output text

# No crown jewels bucket
aws s3 ls | grep iamws-crown-jewels || echo "  (none)"

# No iamws-app-secrets in Secrets Manager
aws secretsmanager list-secrets --query 'SecretList[?Name==`iamws-app-secrets`].Name' --output text
```

Every command above should return empty (or `(none)` for the bucket check). If any of them lists something, return to the matching step above and finish the teardown.
