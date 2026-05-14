# Full-Day Workshop — Crown Jewel Roles & Attack Paths

## Crown jewel roles (admin / `*:*`)
- iamws-prod-deploy-role
- iamws-privileged-admin-role
- iamws-privileged-lambda-role
- iamws-role-chain-end-role  (in IaC, not used by full-day labs)

## Attacker identities by lab
- Lab 2 (CreatePolicyVersion): iamws-policy-developer-user  → self-escalates (no separate target role)
- Lab 3 (Trust Policy Abuse): iamws-role-assumer-user       → iamws-privileged-admin-role
- Lab 6 (PassRole EC2):       iamws-ci-runner-user          → iamws-prod-deploy-role (via iamws-prod-deploy-profile)
- Lab 7 (UpdateFunctionCode): iamws-lambda-developer-user   → iamws-privileged-lambda-role (via iamws-privileged-lambda)
- Lab 8 (Lambda Secrets):     iamws-secrets-reader-user     → iamws-app-lambda-role (exfiltrates env-var secrets from iamws-app-with-secrets; no admin)

## Parallel role versions
Each iamws-*-user has a same-named iamws-*-role with the same policy attached, so the same paths work via role assumption.
