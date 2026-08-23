# Project working agreements

## Ownership and isolation

- Use one branch or worktree per agent task.
- Do not allow two agents to modify the same working tree concurrently.
- Commit or stash work before moving a task between the PC and Mac.
- Treat the pull request as the authoritative cross-device handoff.

## Platform responsibilities

- Treat the PC and Mac as co-equal trusted administrative workstations.
- Run general implementation, large tests, containers, and GPU work on the PC.
- Run Xcode builds, Simulator tests, signing, and Apple-platform validation on
  the Mac.
- Use the N150 for Git coordination and lightweight automation only.
- These responsibilities describe available capabilities, not authority or
  trust.

## Completion

- Record the commands used to validate the change.
- Call out validation that can run only on another platform.
- Do not commit credentials, signing material, generated build directories, or
  machine-specific agent state such as `.codex` or `.claude`.
