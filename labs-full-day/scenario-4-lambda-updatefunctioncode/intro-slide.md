# Scenario 4 — Lambda UpdateFunctionCode

## Slide intro bullets

- `iamws-lambda-developer` can `lambda:UpdateFunctionCode` on `*` — including functions running as a privileged role.
- Overwrite the function's code with one that calls AWS APIs as the function's role.
- iam-recon's `pathfinding` maps this to pathfinding.cloud `[lambda-003]` / `[lambda-004]`. (`argquery --preset privesc` won't catch it — the Lambda edge checker short-circuits when the source principal lacks `iam:PassRole`, even though the attack doesn't require it. Pathfinding catches it via dangerous-permission matching.)
- Pathfinding.cloud category: Lambda-UpdateFunctionCode.

## Learning objective

Participants understand that "update code" on a Lambda is "assume the Lambda's role." The function's execution role is the attacker's payoff, not the code itself.
