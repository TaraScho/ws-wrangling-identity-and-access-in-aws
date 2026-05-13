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

## Narrative thread — "iam-recon as your verification tool"

Weave through every existing defense slide:

- After every remediation, the question is: *did we actually remove the privesc edge, or just the obvious one?*
- iam-recon answers that question in two commands:
  ```bash
  iam-recon graph create --profile taractf
  iam-recon --account $ACCOUNT_ID argquery --preset privesc
  ```
- This is the strongest pedagogical thread the new tool gives us: the same tool that *finds* the attack path *verifies* it's gone.
- Recommended slide pattern: each defense slide gets a "Verify with iam-recon" footer showing the expected diff in `argquery --preset privesc` output.

## Suggested deck structure

1. (Existing) Permissions boundaries
2. (Existing) Trust policies
3. (Existing) Condition keys
4. (Existing) SCPs
5. **NEW** IAM Spy — runtime perspective
6. **NEW** Provers — formal verification
7. **NEW** Tying it together — iam-recon as the loop-closing verification tool

## Open questions for Tara

- Fold IAM Spy + provers into the existing deck or break them into a 3rd lecture?
- Do you want the verification thread as inline footers on existing slides, or as a single capstone slide at the end?
