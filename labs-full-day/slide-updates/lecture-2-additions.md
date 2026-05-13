# Lecture 2 slide-update bullets — defenses + IAM Spy + provers + iam-recon-as-verification

Drop into `Lecture-2-Fencin-the-Frontier.pptx`. Two new sections + one narrative thread woven through existing defense slides.

## New section 1 — "Beyond static analysis: IAM Spy"

- **IAM Spy** = runtime / CloudTrail-driven monitoring of effective IAM behavior.
- Complements iam-recon (which is a static graph): iam-recon predicts what's possible; IAM Spy records what actually happened.
- Use cases: detect when a long-dormant privesc path is actually exercised; audit who used a hardened role since the fix landed.
- TODO Tara/Andrew: confirm IAM Spy origin/repo so we can credit + link.

## New section 2 — "Formally proving policies: provers"

- IAM policy "provers" = SMT-backed tools (e.g., AWS-provided Zelkova-style analysis) that produce mathematical guarantees about effective permissions.
- "Can principal P do action A on resource R under condition C?" — answered yes/no with proof, not heuristics.
- Where they fit: post-remediation verification of high-stakes changes (admin trust policies, cross-account roles).
- TODO Tara/Andrew: name the specific provers we're recommending (Zelkova? CloudSplaining variants? AWS Access Analyzer policy validation?).


## Suggested deck structure

1. (Existing) Permissions boundaries
2. (Existing) Trust policies
3. (Existing) Condition keys
4. (Existing) SCPs
5. **NEW** IAM Spy — runtime perspective
6. **NEW** Provers — formal verification
7. **NEW** Tying it together — iam-recon as the loop-closing verification tool
