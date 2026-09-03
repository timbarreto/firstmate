# Agent-crew landscape and naming constraints

**Wayfinder ticket:** [#19](https://github.com/timbarreto/firstmate/issues/19)  
**Parent map:** [#17](https://github.com/timbarreto/firstmate/issues/17)  
**Research cutoff:** September 2, 2026 Pacific time (September 3, 2026 UTC)  
**Scope:** Open-source positioning and naming research, not legal advice or a final naming decision.

## Executive summary

The agent-orchestration category and its obvious team metaphors are crowded. **Crew**, **fleet**, **swarm**, **squad**, and **agency** are already core terms in visible projects or first-party products: CrewAI, GitHub Copilot CLI `/fleet`, OpenAI Swarm, Agent Squad, and Agency Swarm. A community fork should not position itself as another generic “agent crew framework,” and those terms are weak foundations for a distinctive permanent name.

Firstmate has a narrower and more defensible category story. Its own documentation describes an **agent distribution**: repository-resident instructions, skills, tooling, policies, and state conventions that supervise existing coding-agent processes. Its durable differentiation is not merely parallel execution. It is repository-owned policy, visible workers, explicit task and delivery contracts, restart recovery, and portability across agent harnesses and session backends.

The `Firstmate` namespace is also crowded. A GitHub repository-name search returned 113 repositories containing `firstmate`, including several Windows-specific ports or wrappers. In addition, an active US `FIRSTMATE` software registration and a live `FIRST MATE` software application make a Firstmate-derived permanent identity a material clearance concern.

The recommended launch architecture is therefore:

1. **Near term:** retain `timbarreto/firstmate` as an explicitly experimental community compatibility fork while validating the design-partner promise.
2. **Positioning:** lead with “repository-native agent operations” or “agent operations distribution,” not a generic multi-agent framework claim.
3. **Adoption wedge:** present Windows and GitHub Copilot CLI as the first validated compatibility profile, not the permanent brand boundary.
4. **Permanent identity:** if the fork becomes a lasting independently governed project, prefer a distinct primary brand with prominent factual lineage: “based on Firstmate” and, only after the compatibility contract is defined, “Firstmate-compatible.”
5. **Naming work:** explore distinctive coined or suggestive names outside the occupied crew/fleet/swarm/squad/agency and Firstmate-derived namespaces. Conduct professional clearance before adoption.

## Research method and limits

Facts below were checked against official repositories, official project documentation, GitHub metadata, package registries, and USPTO TSDR records. GitHub metadata was queried through `gh-axi`.

Repository activity dates show that a repository had a push near the cutoff; they do not prove project health, governance quality, or production suitability. Registry checks establish only whether an exact package name was found at the cutoff. Trademark screening is preliminary and does not cover common-law rights, every jurisdiction, every relevant class, domains, companies, or confusingly similar marks.

## 1. Adjacent open-source landscape

### Project map

| Project | Official positioning | Status at cutoff | Positioning implication |
|---|---|---|---|
| [CrewAI](https://github.com/crewAIInc/crewAI) | Framework for collaborative agents organized as **Crews**, with event-driven **Flows** and a substantial project CLI. The official docs lead with agents, crews, and flows. | MIT; pushed September 2, 2026 UTC. | “Crew” is strongly occupied in the multi-agent category. Firstmate should not lead with “agent crew framework.” |
| [LangGraph](https://github.com/langchain-ai/langgraph) | Low-level orchestration framework/runtime for long-running, stateful agents, emphasizing durable execution, streaming, persistence, and human-in-the-loop control. | MIT; pushed September 3, 2026 UTC, still September 2 Pacific. | “Durable orchestration runtime” is an established category. Firstmate should distinguish a repository distribution supervising coding-agent processes from an application runtime. |
| [Microsoft Agent Framework](https://github.com/microsoft/agent-framework) | Framework for building, orchestrating, and deploying agents and multi-agent workflows in Python and .NET, with sequential, concurrent, handoff, group-chat, and Magentic patterns. | MIT; pushed September 2, 2026 UTC. | Competing on generic orchestration patterns would put the fork against large SDK ecosystems. |
| [Microsoft AutoGen](https://github.com/microsoft/autogen) | Framework for multi-agent AI applications and conversations. Its README now says the project is in maintenance mode and directs new projects to Microsoft Agent Framework. | Maintenance mode; last push April 15, 2026. | Even declining projects retain vocabulary and search visibility. “AutoGen” and generic conversation-framework language are poor naming or category anchors. |
| [AG2](https://github.com/ag2ai/ag2) | “AgentOS” and async agent framework that explicitly states it diverged from AutoGen in November 2024. | Apache-2.0; pushed September 2, 2026 UTC. | Useful fork-branding precedent: establish a distinct identity while documenting lineage and migration paths. |
| [OpenAI Agents SDK](https://github.com/openai/openai-agents-python) | Lightweight framework for multi-agent workflows using agents-as-tools, handoffs, guardrails, sessions, and tracing. | MIT; pushed September 2, 2026 UTC. | Manager-agent and handoff language is already generic SDK vocabulary, not a distinctive position by itself. |
| [OpenAI Swarm](https://github.com/openai/swarm) | Experimental educational framework around agents and handoffs. Its README says the OpenAI Agents SDK replaced it for production use. | MIT; last push April 15, 2026. | “Swarm” remains a recognizable occupied term even though the project is superseded. |
| [Agent Squad](https://github.com/2FastLabs/agent-squad) | Lightweight framework for routing among specialized agents in Python, TypeScript, and Swift; formerly `multi-agent-orchestrator` and previously hosted under `awslabs`. | Apache-2.0; pushed September 2, 2026 UTC. | “Squad” is occupied. Its rename also illustrates the cost of changing identity, repository location, bookmarks, and package references. |
| [Agency Swarm](https://github.com/VRSEN/agency-swarm) | Multi-agent orchestration framework organized around an “agency” metaphor. | MIT; pushed August 19, 2026 UTC. | Both “agency” and “swarm” are occupied in the same category. |
| [MetaGPT](https://github.com/FoundationAgents/MetaGPT) | Multi-agent framework modeling a software company through product-manager, architect, project-manager, and engineer roles. | MIT; last push January 21, 2026. | Role-played software-team positioning is already well established. |

Primary sources:

- [CrewAI documentation](https://docs.crewai.com/) and [Flows documentation](https://github.com/crewAIInc/crewAI/blob/main/docs/v1.15.5/en/concepts/flows.mdx)
- [LangGraph overview](https://langchain-ai.github.io/langgraph/index.html)
- [Microsoft Agent Framework orchestrations](https://learn.microsoft.com/en-us/agent-framework/workflows/orchestrations/)
- [AutoGen README](https://github.com/microsoft/autogen/blob/main/README.md)
- [AG2 motivation and history](https://docs.ag2.ai/docs/user-guide/motivation/)
- [OpenAI Agents SDK orchestration](https://openai.github.io/openai-agents-python/multi_agent/)
- [OpenAI Swarm README](https://github.com/openai/swarm/blob/main/README.md)
- [Agent Squad README](https://github.com/2FastLabs/agent-squad)
- [Agency Swarm repository](https://github.com/VRSEN/agency-swarm)
- [MetaGPT repository](https://github.com/FoundationAgents/MetaGPT)

### GitHub Copilot CLI is a direct functional neighbor

GitHub Copilot CLI officially supports Linux, macOS, and Windows through PowerShell and WSL. Its `/fleet` command decomposes an implementation plan into subtasks, manages dependencies, and runs suitable work through parallel subagents with separate context windows.

Sources:

- [About GitHub Copilot CLI](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-copilot-cli)
- [Running tasks in parallel with `/fleet`](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/fleet)
- [Copilot CLI command reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)

This means the following claims are not sufficient differentiation:

- parallel subagents from one prompt;
- task decomposition and dependency management;
- separate context windows;
- Windows availability; or
- a nautical “fleet” metaphor.

### Firstmate's stronger category boundary

Firstmate's [README](../../README.md#what-it-is) says it is not a model, harness, skill, MCP server, application, or CLI; it is an **agent distro**. Its [vision](../../VISION.md#the-fleet-outlives-any-vendor) emphasizes portability across harnesses and session managers. Its current product story also includes visible independent workers, isolated worktrees, explicit ship/research task shapes, project-specific delivery modes, durable state, restart reconciliation, and narrowly scoped merge authority.

Those properties support a more defensible position:

> **A repository-native agent operations distribution for supervising existing coding-agent processes.**

The phrase describes a different layer from application frameworks such as CrewAI or LangGraph and from first-party parallel-subagent execution such as Copilot `/fleet`.

## 2. Firstmate-derived naming collisions

### GitHub namespace crowding

At the cutoff:

- [kunchenguid/firstmate](https://github.com/kunchenguid/firstmate) had approximately 4,676 stars and 1,521 forks.
- GitHub identified [timbarreto/firstmate](https://github.com/timbarreto/firstmate) as its fork.
- A repository search for `firstmate in:name` returned **113 repositories**.

Relevant collisions include:

- [grqg-dev/firstmate](https://github.com/grqg-dev/firstmate), a delegation-first orchestrator skill;
- [horizon0514/firstmate-dsh](https://github.com/horizon0514/firstmate-dsh), manager-centric orchestration for DeepSeek Harness;
- [FallingReign/firstmate-win](https://github.com/FallingReign/firstmate-win), described as a Windows version;
- [leonardorojo/firstmate-win](https://github.com/leonardorojo/firstmate-win), a WSL compatibility wrapper for Windows repositories;
- [mgoyal8293/firstmate-windows](https://github.com/mgoyal8293/firstmate-windows), a Windows-native downstream port; and
- [EvanBatten/firstmate-for-windows](https://github.com/EvanBatten/firstmate-for-windows).

Exact repository-name searches found no repositories for `openfirstmate`, `firstmate-community`, `firstmate-ce`, `firstmate-next`, or `firstmate-copilot` at the cutoff. That is namespace availability, not legal or market clearance.

### Package-registry screening

Exact-name checks at the cutoff found:

- npm: [`first-mate`](https://www.npmjs.com/package/first-mate) exists at version 7.4.3; the other tested names below were not found.
- PyPI: no exact project was found for the tested names.
- NuGet: no exact package was found for the tested names.

Names tested: `firstmate`, `first-mate`, `openfirstmate`, `open-firstmate`, `firstmate-community`, `firstmate-ce`, `firstmate-next`, `firstmate-copilot`, and `firstmate-windows`.

Registry availability can change quickly and should be rechecked immediately before any naming decision.

### Preliminary US trademark screen

The official USPTO TSDR records show:

1. [`FIRSTMATE`, serial 73685186](https://tsdr.uspto.gov/statusview/sn73685186)
   - Registration 1,527,870.
   - Filed September 21, 1987; registered March 7, 1989.
   - Status at the cutoff: live, issued, active, and renewed.
   - International Class 009.
   - Goods include computer programs communicating manufacturing information between machine-monitoring instruments and computers.
   - Owner: Helm Instrument Company, Inc.

2. [`FIRST MATE`, serial 99497048](https://tsdr.uspto.gov/statusview/sn99497048)
   - Filed November 14, 2025.
   - Status at the cutoff: live application; Notice of Allowance issued June 16, 2026.
   - International Class 009 includes downloadable software for sailing and yachting planning and operations.

These records do not decide whether a coding-agent project may use a name. They do establish that an exact-word software registration and a recent exact-phrase software application exist. Adding `Open`, `Community`, `Windows`, `Next`, or a short suffix may not eliminate confusion or clearance risk.

Before investing in a durable Firstmate-derived identity, obtain professional clearance covering at least:

- US Classes 009 and 042;
- confusingly similar and common-law developer-tool uses;
- relevant international databases;
- corporate and domain names; and
- GitHub, npm, PyPI, NuGet, and social namespaces.

### Relative risk of plausible constructions

| Construction | Relative risk | Reason |
|---|---:|---|
| `Firstmate Win`, `Firstmate Windows`, `Firstmate for Windows` | Very high | Existing repositories already use all three patterns, and the name permanently narrows the platform story. |
| `Firstmate Copilot`, `Copilot Firstmate` | Very high | Combines an already crowded upstream identity with GitHub's product mark and can imply endorsement or an official relationship. |
| `Firstmate Community`, `Firstmate CE` | High | Commonly reads as an upstream-authorized edition rather than an independently maintained fork. |
| `Firstmate Next`, `Firstmate NG` | High | Implies official succession or obsolescence of upstream. |
| `OpenFirstmate`, `LibreFirstmate` | High | Keeps the dominant `Firstmate` element and may imply a licensing or governance dispute even though upstream is MIT-licensed. |
| `Firstmate OSS` | Medium-high | Adds little because upstream is already open source and still resembles an official edition. |
| `FirstmateX` or another suffix | Medium-high | Improves exact-string uniqueness but retains pronunciation and dominant-name confusion. |
| Distinct brand with factual Firstmate lineage | Lowest of these directions | Separates identity and governance while preserving attribution and compatibility information; ordinary clearance is still required. |

GitHub's trademark policy treats misleading affiliation as a relevant confusion risk. GitHub's Copilot Extension policy, while written for extensions, is also a useful conservative marketing guardrail: do not state or imply that GitHub developed, endorsed, reviewed, or approved the project.

Sources:

- [GitHub Trademark Policy](https://docs.github.com/en/site-policy/content-removal-policies/github-trademark-policy)
- [GitHub Copilot Extension Developer Policy](https://docs.github.com/en/site-policy/github-terms/github-copilot-extension-developer-policy)

## 3. Maintained community-fork branding norms

### Fact: successful durable forks make identity and lineage separately legible

**Jenkins / Hudson.** The Hudson community voted 214–14 among eligible votes to rename the community project Jenkins. The announcement paired the new identity with explicit community governance and moved the domain, communication channels, and GitHub organization. Current Jenkins trademark guidance recommends constructions such as `<product> for Jenkins` and `<product> compatible with Jenkins` rather than embedding Jenkins as another product's dominant mark.

Sources:

- [Jenkins rename announcement](https://www.jenkins.io/blog/2011/01/29/jenkins/)
- [Jenkins trademark and naming guidance](https://www.jenkins.io/project/trademark/)

**OpenTofu / Terraform.** OpenTofu adopted a distinct name while explicitly describing itself as a Terraform fork, community-governed, and backward-compatible. It preserved the compatibility promise in documentation and migration guidance rather than presenting itself as a Terraform edition.

Sources:

- [OpenTofu fork announcement](https://opentofu.org/blog/opentofu-announces-fork-of-terraform/)
- [OpenTofu migration guidance](https://opentofu.org/docs/intro/migration/)

**AG2 / AutoGen.** AG2 uses a distinct project and package identity while its documentation states that it diverged from AutoGen in November 2024. Lineage remains explicit without making `AutoGen` the dominant current brand.

Source: [AG2 motivation and history](https://docs.ag2.ai/docs/user-guide/motivation/)

### Recommendation: use a two-layer identity

If this fork becomes independently governed and durably maintained:

> **`<Distinct Brand>`**  
> A community-maintained agent operations distribution based on Firstmate.

After ticket [#20](https://github.com/timbarreto/firstmate/issues/20) defines and tests the compatibility contract, the project may also use a bounded factual statement such as “Firstmate-compatible.”

The project should publish:

- the upstream repository and divergence point;
- which configuration, task, and behavior contracts remain compatible;
- which integrations and product choices are downstream-only;
- governance and maintenance ownership;
- required MIT attribution and copyright notices; and
- a non-affiliation statement where confusion is plausible.

Avoid “official continuation,” “successor,” and “Community Edition” without explicit upstream agreement.

## 4. Positioning the Windows and Copilot design-partner wedge

### Facts

- GitHub Copilot CLI officially supports Windows through PowerShell and WSL.
- Copilot `/fleet` already provides prompt decomposition and parallel subagents.
- Upstream Firstmate now documents verified primary and worker support for Copilot CLI and a native-Windows PowerShell bridge.
- The fork's strategic scope is compatibility-first and intends lasting upstream compatibility.

### Recommendation

Treat Windows and GitHub Copilot CLI as the **first compatibility profile**, not the category or permanent brand:

> **A repository-native agent operations layer that gives one supervising agent durable project policy, explicit delivery contracts, visible workers, and portable execution—starting with a first-class Windows and GitHub Copilot CLI profile.**

Design-partner messaging should test value beyond Copilot `/fleet`:

1. **Repository-distributed control** — policy and lifecycle behavior travel with the repository.
2. **Cross-harness portability** — Copilot CLI is the initial target, not the permanent architecture.
3. **Operational contracts** — task shape, merge authority, escalation, and completion evidence are explicit.
4. **Inspectable workers** — workers remain visible and individually addressable.
5. **Recovery and reconciliation** — durable state survives restarts and detects unfinished obligations.
6. **Backend choice** — native Windows, WSL, and future session backends fit beneath one neutral identity.
7. **Policy over concurrency** — the core value is deciding who may do what and how completion is proved, not merely running more agents.

Use `Windows adapter`, `Windows support`, and `Copilot CLI profile` as descriptive component language. Do not put `Windows`, `WSL`, `GitHub`, or `Copilot` in the permanent primary name.

## 5. Naming criteria

A serious permanent-name candidate should be:

1. **Distinctive** — coined or suggestive rather than a generic team noun.
2. **Searchable** — few unrelated software results and no dominant adjacent AI project.
3. **Non-deceptive** — does not imply upstream authorization, GitHub endorsement, or official succession.
4. **Platform-neutral** — excludes Windows, WSL, GitHub, Copilot, and provider names.
5. **Category-extensible** — still works across harnesses, operating systems, and session backends.
6. **Namespace-viable** — GitHub, package, domain, and social identities can be reserved together.
7. **Trademark-screenable** — no close developer-tool or software marks, especially in Classes 009 and 042.
8. **Pronounceable and spellable** — easy to recommend verbally.
9. **Taxonomy-friendly** — supports coherent names for supervisor, worker, backend, profile, and task lifecycle.
10. **Lineage-compatible** — reads naturally in “based on Firstmate” and, if proven, “Firstmate-compatible.”

Avoid roots and dominant metaphors already occupied by adjacent projects:

- `crew`;
- `fleet`;
- `swarm`;
- `squad`;
- `agency`;
- `autogen`;
- `firstmate`; and
- close nautical-rank variants that look like an official Firstmate edition.

## 6. Candidate directions, not final names

### Direction A — distinct coined brand

**Preferred durable direction.** Explore short invented words with no `first`, `mate`, `crew`, `fleet`, provider, or operating-system component.

Brand architecture:

> **`<Coined Brand>`**  
> Repository-native agent operations, based on Firstmate.

This offers the clearest governance separation and best search potential while keeping Firstmate lineage prominent in the descriptor.

### Direction B — delivery and reconciliation metaphor

Explore uncommon compounds or coined derivatives related to:

- dispatch;
- handoff;
- integration;
- delivery;
- readiness; or
- reconciliation.

Avoid generic single words such as `dispatch`, `branch`, and `worktree`, and avoid `fleet` because it now has a direct Copilot CLI meaning.

### Direction C — supervision and recovery metaphor

Explore uncommon concepts related to:

- watch;
- control;
- observability;
- recovery;
- continuity; or
- command.

This direction can communicate the operational layer but needs careful infrastructure and observability-market collision screening.

### Direction D — transitional descriptive fork identity

During design-partner validation, avoid a premature permanent rename:

> `timbarreto/firstmate` — experimental community compatibility fork of Firstmate, starting with Windows and GitHub Copilot CLI.

This is appropriate while the compatibility contract, design-partner promise, and governance model are still being decided. It should not silently become the permanent identity if the fork develops independent governance and a durable roadmap.

## Decision guidance for the launch map

- **Positioning constraint:** do not compete as another generic multi-agent, crew, or fleet framework.
- **Category direction:** lead with repository-native agent operations or agent operations distribution.
- **Launch wedge:** Windows and Copilot CLI belong in compatibility and recruitment messaging, not the permanent name.
- **Near-term identity:** keep the existing fork name during design-partner validation, with explicit independent-community and non-endorsement language.
- **Durable identity direction:** prefer a distinct primary brand plus prominent factual Firstmate lineage.
- **Clearance gate:** do not select a permanent name until #20 defines compatibility language and #21 runs coordinated trademark, namespace, domain, and package clearance.
- **No new Wayfinder ticket needed:** the sharp decisions exposed here are already represented by [#20](https://github.com/timbarreto/firstmate/issues/20), [#21](https://github.com/timbarreto/firstmate/issues/21), and [#22](https://github.com/timbarreto/firstmate/issues/22).
