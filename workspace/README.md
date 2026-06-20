# workspace/

Runtime artifacts for a single feature/task flow.

| File | Author | When |
|------|--------|------|
| requirements.md | Intake | Before Planner runs |
| plan.md | Planner | After human approves requirements.md |
| architecture.md | Planner | Same pass as plan.md |
| decisions.md | Planner (append-only) | Any architectural decision |
| tasks/task-N/test.* | Planner | One file per task, co-located with spec |
| tasks/task-N/spec.md | Pipeline | Written before each implementer/reviewer call; persists per task |
