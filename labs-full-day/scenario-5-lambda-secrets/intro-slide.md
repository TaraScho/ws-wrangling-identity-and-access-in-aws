# Scenario 5 — Lambda secrets in env vars (GetFunctionConfiguration)

## Slide intro bullets

- `iamws-secrets-reader` user has `lambda:GetFunctionConfiguration` — that API returns env vars in plaintext.
- Functions in this account have an `API_TOKEN` env var. No execution required, no code changes needed.
- iam-recon's `analysis` preset flags Lambda functions with sensitive env-var names as a finding.
- Pathfinding.cloud category: Lambda-EnvVarLeak (or similar — verify exact name).

## Learning objective

Participants recognize that "configuration metadata" APIs are credential-disclosure APIs when developers stash secrets in env vars. The fix is architectural (Secrets Manager), not just policy.

## Open question

Outline mentions "UpdateFunctionConfiguration" — if that's a *separate* attack (write env vars to inject creds or alter behavior), this scenario should be split or extended. Currently treated as a typo for **Get**FunctionConfiguration.
