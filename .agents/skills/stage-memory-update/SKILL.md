---
name: stage-memory-update
description: Use when a major Together feature, long bug fix, architecture change, migration, performance investigation, UI animation pass, or complex research task is complete and docs/PROJECT_MEMORY.md should be updated.
---

# Stage Memory Update

## Goal

Close a stage of Together work by preserving durable context for future Codex sessions.

## Workflow

1. Review the completed work:
   - changed files
   - user-visible behavior
   - product or engineering decisions
   - validation commands and results
   - known limitations

2. Update `docs/PROJECT_MEMORY.md` with durable facts:
   - current status
   - completed work
   - key decisions and reasons
   - important files or modules
   - verification results
   - unresolved issues and next steps

3. Respect source priority:
   - current root docs and code are authoritative
   - `docs/superpowers/*` can provide history
   - `.claude/worktrees/*` is historical reference only

4. Do not record:
   - secrets, tokens, credentials
   - private user data
   - full logs unless exact error text is needed
   - speculative conclusions

5. If this is the second or third repeat of the same workflow, propose or create a focused Skill under `.agents/skills/`.

6. Final response must include:
   - what was added to project memory
   - whether verification was run
   - any recommended new or updated Skill

## Quality Bar

- Keep memory concise.
- Prefer facts over narrative.
- Preserve enough context for a future agent to resume without rereading the whole thread.
