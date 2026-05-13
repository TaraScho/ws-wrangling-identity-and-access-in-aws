# Scenario 1 — CreatePolicyVersion self-escalation

## Slide intro bullets

- The setup: `iamws-policy-developer` user has `iam:CreatePolicyVersion` on a customer-managed policy that's attached to themselves.
- The bug: no resource constraint → user can create a v2 policy granting admin and set it as default.
- iam-recon's `pathfinding` maps this to pathfinding.cloud `[iam-001]`. (`argquery --preset privesc` won't catch it — no CreatePolicyVersion edge checker in `src/edges/iam.rs` — which is itself a useful teaching moment about graph-edges vs path-mapping.)
- Pathfinding.cloud category: IAM-CreatePolicyVersion.

## Learning objective

Participants recognize that a permission on an IAM resource the principal can mutate is effectively a permission on the principal itself.
