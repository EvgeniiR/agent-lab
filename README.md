# Controlled AI Software Development Pipeline

Generic agent templates for an AI software development pipeline in [opencode](https://opencode.ai).

Minimal prompt → requirements → plan + tests → implement → independent review → done.

---

## Agents

| Agent | Mode | Does |
|-------|------|------|
| `pipeline` | **orchestrator** | Single entry point. Drives the full flow, pauses at human gates. |
| `intake` | subagent | Expands a vague prompt into `workspace/requirements.md`. No interactive Q&A. |
| `planner` | subagent | Decomposes requirements into tasks + acceptance tests. No code. |
| `implementer` | subagent | Implements one task. Inner loop until tests green. Raises `PLAN DEFECT` instead of silently changing architecture. |
| `reviewer` | subagent | Independently verifies one task. `APPROVE` or `REJECT`. Does not fix. |

---

## Flow

```
opencode run --agent pipeline "describe feature"
    │
    ├─ @intake → workspace/requirements.md → [human: ok / edit]
    ├─ @planner → workspace/plan.md + tests → (task list shown, no gate)
    └─ per task:
         @implementer → tests green (inner loop)
                      → PLAN DEFECT → [human] → @planner
                      → ESCALATION  → [human decides]
         @reviewer → APPROVE → next task
                   → REJECT (code) → retry @implementer (max 3) → [human if stuck]
                   → REJECT (plan) → [human] → @planner
```

Human checkpoints: approve requirements, handle escalations and plan defects. Everything else is automatic.

---

## Deploy to a project

**1. Run init.sh**

```bash
/path/to/agent-lab/init.sh /path/to/your/project
```

Symlinks agent prompts into `opencode-agents/`, copies `opencode.json.template` → `opencode.json`,
and `AGENTS.md.template` → `AGENTS.md`. Existing files are never overwritten.

**2. Customize**

- Create `AGENTS.md`: run `opencode /init` to bootstrap from the codebase, then trim to under 50 lines (stack, test/lint commands, conventions). See design.md §9 on why human-written beats auto-generated.
- Adjust `model` per role in `opencode.json` if needed (see design.md §3 for the recommended model split).

**3. Run**

```bash
opencode run --agent pipeline "build me a CLI tool that parses CSV and outputs JSON"
```

`pipeline` drives the full flow and pauses to ask you at each gate. That's the only command you need.

**Advanced — per-role manual control:**

Each role can also be called independently (useful for debugging or re-running one step):

```bash
opencode run --agent intake "build me a CLI that..."
opencode run --agent planner
opencode run --agent implementer
opencode run --agent reviewer
```

Note: `implementer` and `reviewer` read from `workspace/current_task.md`, which pipeline writes
automatically. For manual calls, create this file first:

```markdown
# Current Task

## TASK-1: <title>

**Goal:** <what this task achieves>
**Acceptance criteria:**
- AC-1: <testable condition>
**Test file:** workspace/tests/task_1_test.<ext>
```

Each call is a fresh session — agents read state from `workspace/` files, not from chat history (design §6).

---

## Repository layout

```
agents/                  # Role prompt templates (source of truth)
  pipeline.md            # Orchestrator — main entry point
  intake.md
  planner.md
  implementer.md
  reviewer.md
workspace/               # Runtime artifacts per feature (created in the target project)
  requirements.md        # Intake output — human-gated
  plan.md                # Planner output
  architecture.md        # Planner output
  decisions.md           # Append-only decision log
  current_task.md        # Pipeline output — active task pointer, overwritten per task
  tests/                 # Acceptance tests authored by Planner
init.sh                  # Deploy agents to a target project (symlinks + config copy)
opencode.json.template   # opencode config template
design.md                # Architecture decision record
```

---

## Key design decisions

- **Tests authored by Planner, not Implementer** — prevents correlated oracle (the implementer testing exactly what it wrote).
- **Reviewer always re-runs tests** — does not trust Implementer's green report.
- **Two REJECT types** — code defect (→ Implementer) vs plan defect (→ Planner). Different escalation paths.
- **3-iteration cap** — if the same task fails 3 reviewer cycles, pipeline escalates to human.
- **Three context layers** — role behavior in agent prompts, stable project facts in `AGENTS.md`, evolving task state in `workspace/`.

See `design.md` for full rationale.
