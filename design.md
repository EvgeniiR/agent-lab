# DESIGN.md — Controlled AI Software Development Pipeline

> Architecture Decision Record for the universal framework.
> Source of truth for architecture. Every new working session (opencode, coding
> assistants, new chat) should start by reading this file.
> Status: design frozen, implementation not yet started.

---

## 1. Goal

Not a multi-agent framework, but a **controlled AI software development pipeline**:
minimal input prompt → requirement expansion → multi-step development →
independent verification → done. Linear pipeline + strict roles + review loop.

Principles:
- Double-check instead of consensus (independent verification, not "multiple agents agreed").
- Context through files, not chat memory (LLM stateless, state lives in artifacts).
- Strict roles: each agent does one thing, roles do not overlap.
- Always a stop-condition (otherwise infinite "improvements").
- Memory = project artifacts, not "memory in the model's head".

---

## 2. Tool choice

**Decision: opencode.**

Rationale: natively provides exactly the needed primitives — primary/subagent, per-agent
model selection (any provider, `provider/model-id` format), per-agent tool permissions
(read-only roles, bash where needed), markdown agent definitions, AGENTS.md for project
context. Terminal-based, the 4-role pipeline fits without an external orchestrator.

Alternatives considered and why not now:
- **Kilo Code CLI** — Roo-style orchestrator mode in terminal, fork of Roo, CLI on top
  of opencode. Real upgrade if manual role stitching in opencode becomes painful. Keep in mind.
- **Forge** — built-in three-role split (implement / research read-only / plan), BYOK
  300+ models. Conceptually close, but new Rust tool.
- **Roo Code** — most mature orchestration (file-regex permissions, Boomerang), but it's
  a VS Code plugin, pulling away from the terminal.
- **Aider** — architect/editor split, benchmark-validated, but it's a 2-role pair, not a
  4-role reviewer-gated pipeline.
- **Provider-locked assistants** — locked to a single model provider, preventing
  cross-provider mixes. Not applicable.

**When to revisit:** if manual loop orchestration (who calls whom, context passing between
roles) becomes painful — look at Kilo Code CLI as a direct upgrade (opencode skill is not
lost, Kilo is built on top of it).

---

## 3. Roles and model distribution

Four roles. Distribution principle: independence of the Implementer↔Reviewer pair
(must use different model providers, otherwise double-check is fictitious) + cost
savings on the most token-heavy role.

| Role | Model | Why |
|------|-------|-----|
| Intake / Requirement Expander | Quality model | Runs once per feature, tiny volume; subtle work (vague → precise, surface assumptions) |
| Planner | Quality model | High-leverage: a bad plan poisons everything downstream, errors are hard to catch |
| Implementer | Budget model | ~80% of all tokens (writes/rewrites code), bulk coding work |
| Reviewer | Quality model (different provider than Implementer) | Quality gate, system ceiling; must be a different provider than Implementer for independence |

The quality model sits on three roles, but two of them (Intake, Planner) are nearly free
due to low volume. The expensive token burn (Implementer) goes to the budget model.
Result: quality-tier results at budget-tier cost on the bulk of work.

Role descriptions:
1. **Intake / Expander** — turns a lazy prompt into a spec, documents assumptions.
   Output: `requirements.md`. (Clarifying questions — NOT interactive, see §5.)
2. **Planner** — architecture + task decomposition + per-task acceptance tests.
   Does NOT write code. Output: `plan.md`, `architecture.md`, tests.
3. **Implementer** — writes code per `plan.md`. Does NOT change architecture.
4. **Reviewer** — independent verification of what tests don't catch.
   APPROVE / REJECT (+reason).

---

## 4. Flow and two nested loops

```text
Intake ──> requirements.md ──[human gate]──>
Planner ──> plan.md + acceptance tests   (tests authored by Planner, NOT Implementer)
        │
        ▼  per task from plan.md (granularity = task, not whole codebase)
  ┌──────────────────────────────────────────────┐
  │ INNER CHEAP LOOP                              │
  │ Implementer:                                  │
  │   writes code → runs tests/linter itself       │
  │   red? fixes itself, Reviewer is NOT called    │
  └──────────────────────────────────────────────┘
        │ only when tests are green
        ▼
  ┌──────────────────────────────────────────────┐
  │ OUTER EXPENSIVE LOOP                          │
  │ Reviewer: judges what tests don't catch       │
  │   edge cases, plan conformance, design        │
  │   can flag PLAN DEFECT (→ back to Planner)    │
  │   APPROVE / REJECT (+reason)                  │
  └──────────────────────────────────────────────┘
        │ APPROVE
        ▼  next task
```

Key mechanics:
- **Tests written by Planner, not Implementer** — otherwise the cost-efficient model
  will test exactly what already works (correlated oracle). The oracle must be
  authored by a different side.
- **Reviewer sees only code that has passed tests** — its expensive tokens are spent on
  subjective judgment, not catching typos.
- **Plan-defect flagging** — Reviewer can flag a *plan* defect, not just a code defect →
  escalation to Planner. This also mitigates weak correlation between same-provider
  Planner and Reviewer.
- **Back-edge Implementer → Planner** — if the plan is unrealizable as written,
  Implementer raises "plan defect" instead of silently changing architecture.

---

## 5. Loop control and stop-conditions

- Limit of **2–3 iterations**, then human decision.
- Escalation presents the human with a **specific disagreement**, not "it didn't work".
- Distinguish two types of unresolved review:
  - *Same bug repeats* → Implementer cannot fix → escalate to human.
  - *New bug each time* → loop doesn't converge → task poorly decomposed → back to Planner.
- Review granularity = **one task** (anchored to decomposition in `plan.md`).
  Stop-condition emerges naturally: task closed → next task.
- **Human checkpoint at the `requirements.md` gate, not interactive Q&A.**
  Expander makes documented assumptions on its own; human reads/edits requirements.md;
  only then Planner starts. This preserves the "minimal prompt" while having a checkpoint.

---

## 6. Three context layers (critical against prompt coupling)

Separation whose violation makes the system brittle:

- **Role prompt** — *how the role behaves*, generic, project-independent. Lives in the agent
  definition (`.opencode/agents/<role>.md`). Contains NO project facts.
- **AGENTS.md** — *stable facts about this project* (stack, build/test/lint commands,
  conventions, non-obvious patterns). Read by all roles automatically. Contains NO role
  behavior — otherwise each role gets polluted with instructions for others.
- **workspace/*.md** — *evolving facts about the current feature* (requirements, plan,
  architecture, decisions). Dynamic memory.

Separator rule: behavior → in agents; stable about project → in AGENTS.md;
evolving about task → in workspace.

---

## 7. Workspace structure

```text
workspace/
  requirements.md    # Intake output, gated by human
  plan.md            # Planner output: task decomposition
  architecture.md    # architecture / current codebase state
  decisions.md       # append-only, with rationale (anti-drift)
  src/
  tests/             # acceptance tests authored by Planner
```

---

## 8. Permissions (per-agent in opencode)

- **Planner** — read-only for code writing (can write only plan/architecture/tests).
- **Reviewer** — read-only for code + **bash** (runs tests/linter).
- **Implementer** — write/edit code + **bash** (runs tests in inner loop).
- **Intake** — writes only requirements.md.

---

## 9. Project adaptation

Mandatory additional layer — **AGENTS.md** (the "how this project works" file that
was missing from the original scheme). Reviewer/Implementer get exact test-run
commands from here.

- opencode reads AGENTS.md automatically, walking up from the current directory;
  hierarchical (closest file to the code wins). Created via `/init`.
- **Keep it short**: root AGENTS.md < 200 lines (in practice 30–50).
- **Do NOT trust auto-generation.** ETH research: LLM-generated context files in
  5 out of 8 setups *worsened* results (+2.45–3.92 steps, +20–23% cost). Human-written
  ones helped. Conclusion: `/init` as a draft, then review and trim manually.

Lighter mechanisms (lightweight, but without them brownfield and re-runs break):
- **Onboarding (brownfield)** — one-time read-only pass: fills `architecture.md`
  with baseline state + draft AGENTS.md. Greenfield skips.
- **Lifecycle / idempotency** — if artifacts already exist, roles *read and append*,
  do not recreate. AGENTS.md updates committed with code (anti-drift).
- **Thin per-project knob** — `.opencode/` of the project + optional per-role
  model overrides. Only commands + models, no DSL. Keep minimal (risk of overengineering).

---

## 10. Two-repo architecture and generation

Goal (destination, NOT first step):
- **Repo A — universal framework**: human-written agent templates + AGENTS.md skeleton.
- **Repo B — project instance**: generated `.opencode/agents/` + AGENTS.md + workspace.

Generation = **thin scaffolder** (cookiecutter-style): copies templates, substitutes
facts (stack, test/lint commands, which roles are active). NOT an LLM prompt generator
(expensive, instance drift from template, imports degradation from ETH research, overengineering).

Project *behavioral* deviations (e.g. security-critical Reviewer with a different checklist)
— through manual per-project override: own `reviewer.md` in project's `.opencode/agents/`
overrides the global one. No generator needed for this.

---

## 11. Implementation sequence (more important than the architecture itself)

**Don't build the generator now — there's nothing to template.** Variation points are
only visible after a live run. Correct order:

1. Write concrete **generic role prompts** as plain files.
2. Validate on **one real project**.
3. See what *actually* changes from project to project.
4. Only then extract templates + write the scaffolder.

A template is a distillation of something already working, not a starting point.
The generator is phase 2, after the first live run.

---

## 12. Tracked risks

- correlated errors (double-check ≠ guaranteed independence) → mitigated by different providers + plan-defect flag.
- goal drift in review/fix cycles → mitigated by per-task granularity + distinguishing rejection types.
- overengineering requirements / tooling → mitigated by "prompts first, generator later" + minimal knob.
- prompt coupling / brittle system → mitigated by three context layers (§6).
- infinite loop without stop-condition → iteration limit + human escalation.
- memory / context drift (stale AGENTS.md, workspace) → lifecycle rule + append-only decisions + commit AGENTS.md with code.

---

## 13. Open question / next step

Write the first real role prompt. **Fork: Reviewer or Intake?**
- *Reviewer* — the most subtle, defines the quality ceiling (REJECT format, boundary
  of "what tests catch vs what the model judges", plan-defect flag). Argument: sets the bar
  that the rest adapt to.
- *Intake* — start of the flow, simpler, gives a quick first end-to-end run.

No decision on this point yet.
