# Project workflow entry point

Follow the repository-root [AGENTS.md](../AGENTS.md). Read it from disk before
executing any kit slash command, including a literal `/tasks` message that the
chat interface has not expanded. Use its Literal Slash Commands mapping to load
the current workspace prompt, role, and referenced workflow instructions.
`/tasks` requests requirement reconciliation and backlog planning, not a task
status summary, even when every existing task is Done.

This is best-effort loading guidance, not an enforced router. For role-restricted
work, the developer should explicitly select the mapped custom agent in the
picker. Do not claim that reading a role file activates its tool permissions.

General questions do not activate the structured workflow or require project
document reads. Do not execute commands merely mentioned in a question.
