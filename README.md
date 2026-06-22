# Controlled AI Software Development Pipeline

Generic agent templates for an AI software development pipeline in [opencode](https://opencode.ai).

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

## Model distribution

| Role | Recommended tier | Why |
|------|-----------------|-----|
| Intake | Quality | Runs once; subtle work — vague → precise, surface assumptions |
| Planner | Quality | High-leverage: a bad plan poisons everything downstream |
| Implementer | Budget | ~80% of all tokens; bulk coding work |
| Reviewer | Quality, **different provider than Implementer** | Quality gate; same-provider double-check is fictitious |

Intake and Planner are nearly free by volume. The expensive token burn goes to the budget model.

### Model configuration profiles

| Profile | Pipeline | Intake | Planner | Implementer | Reviewer | Use when |
|---------|----------|--------|---------|-------------|----------|----------|
| Enterprise max | `opencode/claude-sonnet-4-6` | `opencode/gpt-5.4` | `opencode/claude-opus-4-8` | `opencode/gpt-5.3-codex` | `opencode/claude-opus-4-8` | Quality matters more than cost. |
| Production ready | `deepseek/deepseek-v4-pro` | `opencode/gpt-5.1` | `opencode/claude-sonnet-4-6` | `deepseek/deepseek-v4-pro` | `opencode/claude-sonnet-4-6` | Serious production work with strong independent review. |
| Balanced | `deepseek/deepseek-v4-pro` | `deepseek/deepseek-v4-pro` | `opencode/gpt-5.1` | `deepseek/deepseek-v4-pro` | `opencode/claude-haiku-4-5` | Better planning/review without moving all token-heavy work to premium models. |
| Pet quality bump | `deepseek/deepseek-v4-pro` | `deepseek/deepseek-v4-pro` | `opencode/qwen3.7-plus` | `deepseek/deepseek-v4-pro` | `opencode/qwen3.7-plus` | Recommended low-cost upgrade over using DeepSeek everywhere. |
| Cheap pet | `opencode/deepseek-v4-flash` | `deepseek/deepseek-v4-pro` | `opencode/qwen3.7-plus` | `deepseek/deepseek-v4-pro` | `opencode/qwen3.7-plus` | Lower cost, still keeps planning/review independent. |
| Ultra cheap | `opencode/deepseek-v4-flash` | `opencode/deepseek-v4-flash` | `opencode/qwen3.5-plus` | `opencode/deepseek-v4-flash` | `opencode/minimax-m2.7` | Experiments and drafts only. |

This preserves the main cost advantage because Implementer burns most tokens, while Planner and Reviewer get a different model family for higher-quality planning and independent verification.

After changing `opencode.json`, restart opencode. Model config is loaded at startup.

**When to revisit opencode:** if manual role orchestration becomes painful, look at Kilo Code CLI — built on top of opencode, so the skill transfers directly.

---

## Three context layers

Separation whose violation makes the system brittle:

- **Role prompt** — *how the role behaves*, generic and project-independent. Lives in
  `opencode-agents/<role>.md`. Contains no project facts.
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
/path/to/agent-lab/init.sh /path/to/your/project
```

Symlinks agent prompts into `opencode-agents/`, copies `opencode.json.template` → `opencode.json`.
Existing files are never overwritten.

**2. Customize**

- Create `AGENTS.md`: run `opencode /init` to bootstrap, then **trim and review manually**. ETH research found LLM-generated context files worsened results in 5 of 8 setups (+20–23% cost). `/init` output is a draft, not a final product. Keep root `AGENTS.md` under 50 lines: stack, test/lint/build commands, non-obvious conventions.
- Adjust `model` per role in `opencode.json` if needed. See **Model distribution** below for the recommended split.

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

Note: `implementer` and `reviewer` read from `workspace/tasks/task-N/spec.md`, which pipeline writes
automatically. For manual calls, create this file first (e.g., `workspace/tasks/task-1/spec.md`):

```markdown
# Current Task

## TASK-1: <title>

**Goal:** <what this task achieves>
**Acceptance criteria:**
- AC-1: <testable condition>
**Test file:** workspace/tasks/task-1/test.<ext>
```

Each call is a fresh session — agents read state from `workspace/` files, not from chat history.

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
  tasks/
    task-N/
      spec.md            # Pipeline output — task pointer written before each call
      test.<ext>         # Acceptance tests authored by Planner
init.sh                  # Deploy agents to a target project (symlinks + config copy)
opencode.json.template   # opencode config template
```

---

## Key design decisions

- **Tests authored by Planner, not Implementer** — prevents correlated oracle (the implementer testing exactly what it wrote).
- **Reviewer always re-runs tests** — does not trust Implementer's green report.
- **Two REJECT types** — code defect (→ Implementer) vs plan defect (→ Planner). Different escalation paths.
- **3-iteration cap** — if the same task fails 3 reviewer cycles, pipeline escalates to human.
- **Three context layers** — role behavior in agent prompts, stable project facts in `AGENTS.md`, evolving task state in `workspace/`.
- **Reviewer sees only green code** — expensive tokens spent on judgment (edge cases, plan conformance, design), not catching typos.
- **Plan-defect path from Reviewer** — mitigates correlated errors when Planner and Reviewer share a provider; each can flag the other's output.
