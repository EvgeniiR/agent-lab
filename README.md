# Controlled AI Software Development Pipeline

Generic agent definitions for a controlled AI software development pipeline in [opencode](https://opencode.ai).

Minimal prompt → requirements → plan + tests → implement → independent review → done.

---

## Design principles

- **Double-check, not consensus** — Reviewer is independent verification, not a second vote.
- **State in files, not chat** — all agents are stateless; memory lives in `workspace/` artifacts.
- **Strict roles** — each agent does one thing. Roles do not overlap.
- **Always a stop-condition** — every loop has an iteration cap and a human escalation path.

---

## Agents

| Agent | Mode | Does |
|-------|------|------|
| `agent-lab.pipeline` | **orchestrator** | Single entry point. Drives the full flow, pauses at human gates. |
| `agent-lab.intake` | subagent (hidden) | Expands a vague prompt into `<run-dir>/requirements.md`. No interactive Q&A. |
| `agent-lab.planner` | subagent (hidden) | Decomposes requirements into tasks + acceptance tests. No code. |
| `agent-lab.implementer` | subagent (hidden) | Implements one task. Inner loop until tests green. Raises `PLAN DEFECT` instead of silently changing architecture. |
| `agent-lab.reviewer` | subagent (hidden) | Independently verifies one task. `APPROVE` or `REJECT`. Does not fix. |

---

## Flow

All artifacts for a run live under `workspace/<YYYYMMDD-HHMM-slug>/` (the run dir, created
by pipeline Phase 0). Paths below are relative to that run dir.

```
opencode run --agent agent-lab.pipeline "describe feature"
    │
    ├─ @agent-lab.intake → <run-dir>/requirements.md → [human: ok / edit]
    ├─ @agent-lab.planner → <run-dir>/plan.md + tests → (task list shown, no gate)
    └─ per task:
         @agent-lab.implementer → tests green (inner loop)
                       → PLAN DEFECT → [human] → @agent-lab.planner
                       → ESCALATION  → [human decides]
         @agent-lab.reviewer → APPROVE → next task
                    → REJECT (code) → retry @agent-lab.implementer (max 3) → [human if stuck]
                    → REJECT (plan) → [human] → @agent-lab.planner
```

Human checkpoints: approve requirements, handle escalations and plan defects. Everything else is automatic.

---

## Model distribution

| Role | Recommended tier | Why |
|------|-----------------|-----|
| Intake | Quality | Runs once; subtle work — vague → precise, surface assumptions |
| Planner | Quality | High-leverage: a bad plan poisons everything downstream |
| Implementer | Budget | ~80% of all tokens; bulk coding work |
| Reviewer | Quality, **different provider than Implementer** | Quality gate; same-provider double-check is fictitious |

Intake and Planner are nearly free by volume. The expensive token burn goes to the budget model.

---

## Three context layers

Separation whose violation makes the system brittle:

- **Role prompt** — *how the role behaves*, generic and project-independent. Lives in
  `.opencode/agents/agent-lab.<role>.md` (a self-contained markdown file: YAML frontmatter
  for model/permissions/mode + body for the prompt). Contains no project facts.
- **AGENTS.md** — *stable facts about this project* (stack, test/lint commands, conventions,
  non-obvious patterns). Read automatically by all roles. Contains no role behavior —
  otherwise each role gets polluted with instructions meant for others.
- **`workspace/*.md`** — *evolving facts about the current feature* (requirements, plan,
  architecture, decisions). Dynamic memory.

Separator rule: behavior → agent prompts; stable project facts → AGENTS.md; evolving task facts → workspace.

---

## Deploy to a project

**1. Run init.sh**

```bash
# Default profile (all DeepSeek v4 Pro)
/path/to/agent-lab/init.sh /path/to/your/project

# Advanced profile (intake/reviewer on Qwen3.7, planner on GLM-5.2,
# implementer on DeepSeek v4 Pro, pipeline on DeepSeek v4 Flash)
/path/to/agent-lab/init.sh /path/to/your/project advanced
```

Symlinks the chosen profile's agent files into `.opencode/agents/agent-lab.<role>.md`.
opencode auto-discovers `.opencode/agents/*.md`, so **no `opencode.json` is created** —
model, permissions, mode, and prompt all live in each agent file's frontmatter + body.
Existing real files are never overwritten.

**Available profiles:**

| Profile | Pipeline | Intake | Planner | Implementer | Reviewer |
|----------|----------|--------|---------|-------------|----------|
| `default` | `deepseek/deepseek-v4-pro` | `deepseek/deepseek-v4-pro` | `deepseek/deepseek-v4-pro` | `deepseek/deepseek-v4-pro` | `deepseek/deepseek-v4-pro` |
| `advanced` | `deepseek/deepseek-v4-flash` | `opencode-go/qwen3.7-plus` | `opencode-go/glm-5.2` | `deepseek/deepseek-v4-pro` | `opencode-go/qwen3.7-max` |

> The `advanced` profile uses the `opencode-go/` provider for Qwen3.7 / GLM-5.2. That
> provider must exist in your opencode setup or model resolution will fail at startup —
> adjust the `model:` field in the agent files if your gateway uses a different provider id.

**2. Customize**

- Create `AGENTS.md`: run `opencode /init` to bootstrap, then **trim and review manually**. ETH research found LLM-generated context files worsened results in 5 of 8 setups (+20–23% cost). `/init` output is a draft, not a final product. Keep root `AGENTS.md` under 50 lines: stack, test/lint/build commands, non-obvious conventions.
- To change a model for a role, edit the `model:` line in `.opencode/agents/agent-lab.<role>.md` (replace the symlink with a copy first, or edit the source in this repo). See **Model distribution** below for the recommended split.

**3. Run**

```bash
opencode run --agent agent-lab.pipeline "build me a CLI tool that parses CSV and outputs JSON"
```

`agent-lab.pipeline` drives the full flow and pauses to ask you at each gate. That's the only command you need.

**Resuming a run:**

The pipeline pauses at the requirements gate. Continue the same session (instead of
starting a new one) with `--continue`:

```bash
opencode run --agent agent-lab.pipeline "build me a CLI that parses CSV and outputs JSON"
# ... pipeline writes requirements.md and stops at the gate ...
opencode run --agent agent-lab.pipeline --continue "ok"     # approve and proceed
```

Always repeat `--agent agent-lab.pipeline` on `--continue` — otherwise opencode resumes with the
default primary agent and the orchestration logic is lost.

**Note — the role agents are hidden subagents, not direct entry points.** `agent-lab.intake`,
`agent-lab.planner`, `agent-lab.implementer`, and `agent-lab.reviewer` are declared
`mode: subagent` and `hidden: true`, so they don't appear in the `@` autocomplete menu and
`opencode run --agent agent-lab.intake ...` will **not** run them — opencode prints *"agent is a
subagent, not a primary agent"* and falls back to the default `build` agent. They are invoked only
by `agent-lab.pipeline` (via the Task tool), which passes each one its `--workspace <run-dir>` and
spec path automatically. To drive a single role by hand for debugging, temporarily set `hidden:
false` and `mode: primary` in that agent's `.md` file.

---

## Repository layout

```
agents/                         # Agent definitions (source of truth) — markdown with frontmatter
  default/                      # default profile (all DeepSeek v4 Pro)
    pipeline.md                 # Orchestrator — main entry point (mode: primary)
    intake.md                   # mode: subagent, hidden: true
    planner.md
    implementer.md
    reviewer.md
  advanced/                     # advanced profile (mixed models)
    pipeline.md
    intake.md
    planner.md
    implementer.md
    reviewer.md
workspace/                      # Runtime artifacts (created in the target project)
  <YYYYMMDD-HHMM-slug>/         # One run dir per feature (pipeline Phase 0)
    run.json                    # Run metadata: feature, slug, created_at, approved_tasks
    requirements.md             # Intake output — human-gated
    plan.md                     # Planner output
    architecture.md             # Planner output
    decisions.md                # Append-only decision log
    tasks/
      task-N/
        spec.md                 # Pipeline output — task pointer written before each call
        test.<ext>              # Acceptance tests authored by Planner
init.sh                         # Deploy agents to a target project (symlinks into .opencode/agents/)
```

In the target project, `init.sh` creates:

```
<project>/.opencode/agents/
  agent-lab.pipeline.md   -> <agent-lab>/agents/<profile>/pipeline.md
  agent-lab.intake.md     -> <agent-lab>/agents/<profile>/intake.md
  agent-lab.planner.md    -> <agent-lab>/agents/<profile>/planner.md
  agent-lab.implementer.md -> <agent-lab>/agents/<profile>/implementer.md
  agent-lab.reviewer.md   -> <agent-lab>/agents/<profile>/reviewer.md
```

The agent name is the filename without `.md`, prefixed `agent-lab.` to avoid collisions
with built-in agents (`build`, `plan`) and any project-specific agents.

---

## Key design decisions

- **Tests authored by Planner, not Implementer** — prevents correlated oracle (the implementer testing exactly what it wrote).
- **Reviewer always re-runs tests** — does not trust Implementer's green report.
- **Two REJECT types** — code defect (→ Implementer) vs plan defect (→ Planner). Different escalation paths.
- **3-iteration cap** — if the same task fails 3 reviewer cycles, pipeline escalates to human.
- **Three context layers** — role behavior in agent prompts, stable project facts in `AGENTS.md`, evolving task state in `workspace/`.
- **Reviewer sees only green code** — expensive tokens spent on judgment (edge cases, plan conformance, design), not catching typos.
- **Plan-defect path from Reviewer** — mitigates correlated errors when Planner and Reviewer share a provider; each can flag the other's output.
