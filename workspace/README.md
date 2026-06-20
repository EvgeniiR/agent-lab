# workspace/

Runtime artifacts for a single feature/task flow. Created fresh per feature.

| File | Author | When |
|------|--------|------|
| requirements.md | Intake | Before Planner runs |
| plan.md | Planner | After human approves requirements.md |
| architecture.md | Planner | Same pass as plan.md |
| decisions.md | Planner (append-only) | Any architectural decision |
| tests/task_N_test.* | Planner | One file per task |
| current_task.md | Pipeline | Overwritten before each implementer/reviewer call |
