# Controlled AI Software Development Pipeline

Generic agent templates for a 4-role AI development pipeline in [opencode](https://opencode.ai).

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
    ├─ @planner → workspace/plan.md + tests
    └─ per task:
         @implementer → tests green (inner loop)
         @reviewer → APPROVE → next task
                   → REJECT (code) → retry @implementer (max 3)
                   → REJECT (plan) → [human] → @planner
                   → ESCALATION → [human decides]
```

Human checkpoints: approve requirements, handle escalations. Everything else is automatic.

---

## Deploy to a project

**1. Copy agent prompts**

```bash
mkdir -p opencode-agents
cp /path/to/agent-lab/agents/*.md opencode-agents/
```

**2. Create opencode.json**

Copy `opencode.json.template` → `opencode.json` in your project root.
Adjust `model` per role if needed (see design.md §3 for the recommended model split).

**3. Create AGENTS.md**

Copy `AGENTS.md.template` → `AGENTS.md`. Fill in your stack, test/lint commands, conventions.
Keep it under 50 lines — opencode reads this automatically and passes it to every agent.

**4. Run**

```bash
opencode run --agent pipeline "build me a CLI tool that parses CSV and outputs JSON"
```

`pipeline` drives the full flow and pauses to ask you at each gate. That's the only command you need.

**Advanced — per-role manual control:**

Each role can also be called independently (useful for debugging or re-running one step):

```bash
opencode run --agent intake "build me a CLI that..."
opencode run --agent planner
opencode run --agent implementer "implement TASK-1"
opencode run --agent reviewer "review TASK-1"
```

Each call is a fresh session — agents read state from `workspace/` files, not from chat history (design §6).

---

## Repository layout

```
agents/                  # Role prompt templates (source of truth)
  intake.md
  planner.md
  implementer.md
  reviewer.md
workspace/               # Runtime artifacts per feature (created in the target project)
  requirements.md        # Intake output — human-gated
  plan.md                # Planner output
  architecture.md        # Planner output
  decisions.md           # Append-only decision log
  tests/                 # Acceptance tests authored by Planner
AGENTS.md.template       # Project context template
opencode.json.template   # opencode config template
design.md                # Architecture decision record
```

---

## Key design decisions

- **Tests authored by Planner, not Implementer** — prevents correlated oracle (DeepSeek testing exactly what it wrote).
- **Reviewer always re-runs tests** — does not trust Implementer's green report.
- **Two REJECT types** — code defect (→ Implementer) vs plan defect (→ Planner). Different escalation paths.
- **3-iteration cap** — same bug recurring → escalate to human. New bug each time → task too coarse → back to Planner.
- **Three context layers** — role behavior in agent prompts, stable project facts in `AGENTS.md`, evolving task state in `workspace/`.

See `design.md` for full rationale.
