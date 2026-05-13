# Scenario 3 — PassRole + EC2 (missing `iam:PassedToService`)

## Slide intro bullets

- `iamws-ci-runner` has `iam:PassRole` for `iamws-prod-deploy-role` with no `iam:PassedToService` condition.
- Attacker passes the privileged role to a new EC2 instance and exfiltrates creds via IMDS.
- iam-recon's EC2 edge checker catches this exact pattern.
- Pathfinding.cloud category: EC2-PassRole.

## Learning objective

Participants understand that `iam:PassRole` without a service condition is a generic privesc primitive — the destination service determines the attack surface.
