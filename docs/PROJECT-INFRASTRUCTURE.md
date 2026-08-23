# Shared development infrastructure

This file is a map to the live operating information for this project. It is
not a copy of that information. When an address, SSH key, machine capability,
or Forgejo procedure matters, read the canonical document before acting.

## Canonical source of truth

The private Forgejo repository `robert/workspace-infrastructure` owns the live
shared-development documentation.

| Machine | Normal checkout |
| --- | --- |
| Windows PC | `D:\Projects\systems\N150\forgejo` |
| MacBook Neo | `~/Projects/workspace-infrastructure` |
| N150 live service | `/srv/forgejo` (deployment; not a development checkout) |

Read these files in that repository:

- `README.md` — Forgejo endpoints, storage, service boundaries, and backups.
- `SHARED_DEVELOPMENT_GUIDE.md` — PC/Mac/N150 responsibilities, branches,
  pull requests, worktrees, handoffs, validation, and current machine details.
- `SSH_ACCESS_BRIEF.md` — SSH trust model, aliases, ports, key separation,
  verification, and revocation.
- `FORGEJO_AUTOMATION.md` — safe repository, pull-request, issue, Actions, and
  merge API operations through the N150 helper.
- `AGENTS.md` — safety boundaries for changing Forgejo itself.

Device-specific live handbooks remain with the device workspaces on the
Windows PC. Consult them when a task touches that machine rather than relying
on a copied summary:

- `D:\Projects\systems\N150\README.md` and `AGENTS.md` — current N150 service
  inventory, access, recovery boundaries, and subsystem document routing;
- `D:\Projects\systems\Macbook Neo\README.md` — MacBook Neo access and shared
  Apple-development operating notes;
- `D:\Projects\systems\RogAllyX\HANDBOOK.md` and `ally-access.md` — ROG Ally X
  system state, access, maintenance, streaming, and recovery references.

On another workstation, retrieve the relevant private system repository from
Forgejo or use an approved SSH path to read its current handbook. Do not copy
credentials or `*.local.md` files into a project.

If the local infrastructure checkout is unavailable, clone it from
`forgejo-n150:robert/workspace-infrastructure.git` on Windows or
`n150-forgejo:robert/workspace-infrastructure.git` on the Mac.

## Quick orientation

- Forgejo is the private Git source of truth and runs on the always-on N150.
- `origin` is normally Forgejo. Use `github` for an owner-controlled GitHub
  mirror and `upstream` for a third-party source.
- The PC and Mac are co-equal trusted administrative workstations. Use the PC
  for general, container, GPU, and large-test work; use the Mac for Xcode,
  Apple SDKs, Simulator/device testing, signing, and Apple-platform validation.
- The N150 provides Forgejo, backups, repository coordination, and lightweight
  automation. It is not a normal build machine.
- Every machine uses a local clone on its native filesystem. Never build from
  an SMB-mounted working tree.

## Access available to an agent

From the Windows PC, the established SSH aliases are:

- `minipc` — N150 administrative SSH;
- `forgejo-n150` — Forgejo Git SSH (not a shell);
- `macbook-neo` — MacBook Neo SSH for non-interactive development and builds.
- `ally` — ROG Ally X over mDNS; `ally-ip` and `ally-dock` are the reserved-IP
  fallbacks documented in `systems\RogAllyX\ally-access.md`;
- `router` — home router administration when a network task explicitly needs
  it; inspect the relevant system handbook before changing router state.

From the Mac, the established aliases are:

- `n150` — N150 administrative SSH;
- `n150-forgejo` or `forgejo-n150` — Forgejo Git SSH;
- `workout-vps` — production VPS administrative SSH.

Aliases, addresses, fingerprints, privileges, limitations, and safe access
checks can change. Treat `SSH_ACCESS_BRIEF.md`,
`SHARED_DEVELOPMENT_GUIDE.md`, and the relevant device handbook as
authoritative. A password or token prompt on a normally key-only path is
unexpected: stop rather than pasting a credential. Never print, copy, or read
private keys, `secrets.local.md`, or the root-held Forgejo API token.

## Project startup checklist

1. Read this repository's `AGENTS.md`, `README.md`, and relevant subsystem docs.
2. Run `git status --short --branch`, `git remote -v`, and
   `git worktree list` before changing anything.
3. Read the canonical shared guide and SSH brief before cross-device or
   infrastructure work.
4. Use a separate branch or worktree for each task.
5. Keep secrets, production data, generated output, signing material, and
   machine-level agent state out of Git.
6. Record exact validation and any remaining platform-specific checks in the
   pull request or `docs/handoffs/`.
