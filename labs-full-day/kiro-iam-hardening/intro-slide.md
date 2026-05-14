# Kiro IAM Hardening Lab

## Slide intro bullets

- Replace an `Action: *, Resource: *` EC2 instance role with a least-privilege role generated from a Kiro Spec.
- Spec-driven workflow forces requirements (REQ-001..REQ-009) **before** any policy JSON is written.
- AWS IaC MCP Server validates the generated template; AWS Documentation MCP Server answers condition-key questions inline.
- IAM Policy Simulator is the final gate — confirm both allowed *and* denied actions against the deployed role.
- Pre-staged CloudFormation: `assets/insecure-role.yaml` (the bad role) + `assets/analytics-bucket.yaml` (TLS-only bucket with an easter-egg report).

## Learning objective

Participants experience the spec → MCP-validate → simulate loop end-to-end, and walk away with a repeatable pattern for hardening an AWS IAM role using an agentic IDE instead of hand-crafting JSON.
