---
name: feature-flag-retirement
description: >-
  Author feature-flag retirement briefs with an explicit permanent behavior.
  Use before briefing or revising flag-removal work, including an already-approved
  enabled-state retirement or a removal request whose end state is still unclear.
user-invocable: false
metadata:
  internal: true
---

# Feature-flag retirement

Choose the permanent behavior before delegating implementation, then carry that choice into every affected worker's brief.
Retiring a flag and proving a flag unused are different tasks.

1. Identify the exact flag and the requested end state from the current instruction or an already-authorized decision.
   If enabled versus disabled behavior is unresolved, settle that product choice before dispatch rather than giving several workers contradictory assumptions.
   Permission to create a PR or defer governance evidence is not by itself permission to choose a permanent product behavior.
2. For an explicitly authorized permanently enabled outcome, use the enabled-retirement ship scaffold owned by [`bin/fm-brief.sh`](../../../bin/fm-brief.sh); its header and help own invocation, accepted identifiers, and the generated worker contract.
   This is an explicit selection for the named flag, not a default for other flags or projects.
3. Fill the intent subsection with the user's actual request and applicable decision, and keep implementation directions in the specification subsection.
   Align those directions, the proposed title, and the requested evidence with the generated retirement contract.
   Live readers are expected when removing an active gate; describe the actual consumer changes rather than promising an unused-switch or universally behavior-preserving cleanup.
4. Preserve the selected delivery path, requested validation restrictions, and separate merge authority.
   When governance evidence is explicitly deferred to PR approval, record the missing evidence there without converting it into a worker launch blocker.
   A newly discovered behavior choice outside the approved end state still needs a decision.
5. If a worker already stopped on the now-settled choice, deliver the keyed decision through the existing instruction inbox and use `stuck-crewmate-recovery` when its endpoint cannot receive the continuation.
   A recorded answer is not proof that the worker acknowledged or resumed it; reconcile the task's actual outcome.

The brief is ready when it names the exact flag, carries an authorized permanent behavior without a conflicting unused-switch premise, and retains the task's delivery and safety constraints.
