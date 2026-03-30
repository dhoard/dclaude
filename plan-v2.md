# Plan V2: Dockerized Claude Code And Codex With Path Fidelity

## Goal

Build a boring local Docker workflow for Claude Code and Codex where:

- the agent runs inside Docker
- the repo is not copied
- the host and container see the same live working tree
- important host paths have the same absolute path inside the container
- the only user-facing entrypoints are `dclaude` and `dcodex`

This is optimized for a markdown-based review loop:

- you ask the agent to create `plan.md`
- the agent writes that file into the repo
- the agent refers to the real host path
- you open and edit that exact same file locally
- the agent sees your changes immediately

## Changes From V1

V2 makes four explicit changes based on your comments:

- `dclaude` and `dcodex` are the primary and only documented entrypoints
- API-key auth for Claude and Codex is not supported at all
- the plan no longer depends on editor-specific helper commands
- path identity is the core ergonomic primitive, not `/workspace`

There can still be an internal shared helper script if it reduces duplication, but that is implementation detail, not part of the UX.

## Primary UX

The default commands are:

```bash
./dclaude
./dcodex
```

Or, if installed somewhere on `PATH`:

```bash
dclaude
dcodex
```

There should be no expectation that the user runs `agent-run`.

## Non-Negotiable Constraints

- Do not copy the repo into the container.
- Bind-mount the repo read/write.
- Bind-mount important host paths to the same absolute paths they have on the host.
- Mount `~/Desktop` read-only.
- Mount `~/Downloads` read-only.
- Do not mount `docker.sock`.
- Do not use privileged mode.
- Do not mount the full host home directory.
- Run as the current host UID/GID.
- Keep network enabled in the default profile.
- Use only the official interactive login flow for Claude Code.
- Use only the official interactive login flow for Codex.
- Do not support API-key auth for Claude Code or Codex.
- Persist only the minimum scoped Claude/Codex state needed to stay logged in.
- Optional GitHub access should use forwarded SSH agent access, not copied key files.

## Core Design Choice: Path Fidelity

The container should see the same important absolute paths that the host sees.

If the host has:

- repo: `/Users/stanislavkozlovski/code/project`
- Desktop: `/Users/stanislavkozlovski/Desktop`
- Downloads: `/Users/stanislavkozlovski/Downloads`

then the container should also see:

- `/Users/stanislavkozlovski/code/project`
- `/Users/stanislavkozlovski/Desktop`
- `/Users/stanislavkozlovski/Downloads`

That way:

- if the agent says `/Users/.../plan.md`, that path is real on the host
- if you paste `~/Desktop/image.png`, that path is real in the container
- no translation layer is needed

`/workspace` can still exist, but only as a symlink alias to the repo root for compatibility. It is not the canonical path.

## Runtime Model

Assume:

- host home: `/Users/stanislavkozlovski`
- repo root: `/Users/stanislavkozlovski/code/project`
- current working directory: `/Users/stanislavkozlovski/code/project/subdir`

Inside the container:

- `HOME=/Users/stanislavkozlovski`
- repo root exists at `/Users/stanislavkozlovski/code/project`
- current working directory is `/Users/stanislavkozlovski/code/project/subdir`
- `~/Desktop` exists and is read-only
- `~/Downloads` exists and is read-only
- `/workspace` points to `/Users/stanislavkozlovski/code/project`

This is the important part:

- `~` resolves the same way for both you and the agent
- the current repo path is identical on both sides
- files under Desktop and Downloads are directly referenceable without mental mapping

## Auth Model

### Claude Code

Supported auth model:

- interactive login from inside the container
- persisted state via mounted host paths

Mounted paths:

- `~/.claude`
- `~/.config/claude-code`

Not supported:

- `ANTHROPIC_API_KEY`
- `.env`-driven Anthropic auth
- custom auth services

### Codex

Supported auth model:

- interactive login from inside the container
- persisted state via mounted host paths

Mounted path:

- `~/.codex`

Set:

- `CODEX_HOME=~/.codex`

Not supported:

- `OPENAI_API_KEY`
- `.env`-driven OpenAI auth
- custom auth services

### Important Clarification

Claude/Codex login state should be mounted, not copied.

That means:

- `~/.claude`, `~/.config/claude-code`, and `~/.codex` remain on the host
- the container sees them through narrow bind mounts
- login persists across runs without drift

Repo-level files such as `CLAUDE.md`, `AGENTS.md`, or `plan.md` are different. Those are already available because the repo itself is bind-mounted.

## GitHub Access Model

### Recommended Optional Mode

If GitHub SSH access is needed from inside the container, use forwarded SSH agent access.

Recommended runtime additions:

- mount `/run/host-services/ssh-auth.sock`
- set `SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock`
- optionally mount `~/.ssh/known_hosts` read-only

Do not:

- copy SSH keys into the image
- copy SSH keys into container-local state
- mount the entire `~/.ssh` directory

This gives the container signing access through the host agent without handing it raw private key files.

### Operational Recommendation

Do not forward your main general-purpose agent if you can avoid it.

Better setup:

- create a dedicated GitHub SSH key for container use
- load it into a dedicated `ssh-agent`
- forward only that agent socket into the container

That keeps the blast radius smaller.

### Host Prerequisites

Before enabling GitHub SSH mode, the host should already pass:

```bash
ssh-add -L
ssh -T git@github.com
```

### Container Verification

When GitHub SSH mode is enabled, the container should pass:

```bash
echo "$SSH_AUTH_SOCK"
ssh-add -L
ssh -T git@github.com
```

## Docker Security Boundary

Default hardening:

- `--cap-drop=ALL`
- `--security-opt=no-new-privileges:true`
- `--init`

Explicitly omitted:

- `--privileged`
- `docker.sock`
- full `~/.ssh` mount
- full home-directory mount
- host sudo

Important tradeoff:

- anything reachable inside the container is reachable by the agent

That includes mounted auth state and forwarded agent capabilities. This setup is for trusted repos, not hostile ones.

## User-Facing Commands

### `dclaude`

Purpose:

- start the Docker container
- mount the right paths
- set UID/GID correctly
- set the working directory to the current repo path
- start Claude Code in the container

Default launch target:

```bash
claude --dangerously-skip-permissions
```

### `dcodex`

Purpose:

- start the Docker container
- mount the right paths
- set UID/GID correctly
- set the working directory to the current repo path
- start Codex in the container

Default launch target:

- current full-access Codex invocation, validated against the installed CLI version during implementation

Do not hardcode stale flags without verifying the actual installed release.

## Files To Add

### Required

- `Dockerfile`
- `dclaude`
- `dcodex`
- `docker-compose.yml`
- `README.md`

### Optional Internal Helper

If shared logic is needed, add one internal helper such as:

- `scripts/agent-common.sh`

That file is implementation detail. The user-facing interface remains `dclaude` and `dcodex`.

### Files To Update

- `.gitignore` if repo-local helper files are introduced
- `README.md`
- `ARCHITECTURE.md` only if the implementation introduces additional persistent state worth documenting

### Files To Omit

Do not add `.env.example` for Claude/Codex auth.

If an env file is ever introduced for non-auth runtime knobs, it should be optional and clearly separated from authentication. V2 does not require it.

## File Responsibilities

### `Dockerfile`

Base image:

- Python 3.12 slim, unless a concrete reason appears to use 3.13

Install:

- Python
- uv
- git
- curl
- build-essential
- ripgrep
- fd
- jq
- Node 22
- `@anthropic-ai/claude-code`
- `@openai/codex`

Implementation notes:

- install both official CLIs at build time
- keep the image clean and inspectable
- disable Claude auto-update by default so rebuilds remain explicit
- include what is needed for `realpath`, SSH client operations, and standard Python development

### `dclaude`

Responsibilities:

- detect repo root and current working directory
- validate Docker is available
- validate `~/Desktop` and `~/Downloads` exist
- create missing minimal host state directories if needed
- mount the repo at its same absolute host path
- mount `~/Desktop` read-only at the same path
- mount `~/Downloads` read-only at the same path
- mount Claude state paths
- mount shared caches
- optionally enable GitHub SSH forwarding
- run as host UID/GID
- set `HOME` to the host home path
- set the container workdir to the current host repo path
- create `/workspace` symlink to the repo root before launching Claude

### `dcodex`

Responsibilities:

- same runtime model as `dclaude`
- mount Codex state path
- set `CODEX_HOME`
- verify and launch the correct current Codex full-access command

### `docker-compose.yml`

Compose is secondary, not primary.

Use it only if it stays thin and aligned with the scripts.

Preferred shape:

- one service for Claude
- one service for Codex
- same-path mounts
- same UID/GID mapping
- same optional SSH agent forwarding profile
- same `/workspace` symlink behavior

Service names can match the command names:

- `dclaude`
- `dcodex`

## Mount Spec

Assume:

- `HOST_HOME="$HOME"`
- `PROJECT_ROOT="$(git rev-parse --show-toplevel)"`
- `CURRENT_PATH="$PWD"`

Default bind mounts should be equivalent to:

```text
type=bind,src=$PROJECT_ROOT,dst=$PROJECT_ROOT
type=bind,src=$HOST_HOME/Desktop,dst=$HOST_HOME/Desktop,readonly
type=bind,src=$HOST_HOME/Downloads,dst=$HOST_HOME/Downloads,readonly
type=bind,src=$HOST_HOME/.claude,dst=$HOST_HOME/.claude
type=bind,src=$HOST_HOME/.config/claude-code,dst=$HOST_HOME/.config/claude-code
type=bind,src=$HOST_HOME/.codex,dst=$HOST_HOME/.codex
type=bind,src=$HOST_HOME/.cache/pip,dst=$HOST_HOME/.cache/pip
type=bind,src=$HOST_HOME/.cache/uv,dst=$HOST_HOME/.cache/uv
```

Per-tool rules:

- `dclaude` mounts Claude state
- `dcodex` mounts Codex state
- shared caches mount for both

Optional GitHub SSH additions:

```text
type=bind,src=/run/host-services/ssh-auth.sock,dst=/run/host-services/ssh-auth.sock
type=bind,src=$HOST_HOME/.ssh/known_hosts,dst=$HOST_HOME/.ssh/known_hosts,readonly
```

## Environment

Default environment:

- `HOME=$HOST_HOME`
- `PIP_CACHE_DIR=$HOST_HOME/.cache/pip`
- `UV_CACHE_DIR=$HOST_HOME/.cache/uv`

Claude-specific:

- `DISABLE_AUTOUPDATER=1`

Codex-specific:

- `CODEX_HOME=$HOST_HOME/.codex`

Optional GitHub SSH:

- `SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock`

No API-key env vars should be supported for Claude or Codex.

## Working Directory Rules

Canonical working directory:

- the actual host repo path you launched from

Compatibility alias:

- `/workspace` symlink to the repo root

The implementation should prefer truthful paths in prompts, logs, and docs.

## README Requirements

The README should explain:

- why the repo is bind-mounted instead of copied
- why same-path mounting is the core ergonomic choice
- that the repo is available at its real host path
- that `/workspace` exists only as a compatibility alias
- that `~/Desktop` is visible read-only at the same path
- that `~/Downloads` is visible read-only at the same path
- where Claude auth/config state is persisted
- where Codex state is persisted
- that those auth paths are mounted, not copied
- how interactive login works for Claude Code
- how interactive login works for Codex
- why API-key auth is intentionally unsupported
- how optional GitHub SSH access works
- why full `~/.ssh` is intentionally not mounted
- why `docker.sock` is intentionally omitted
- how to rebuild the image
- how to verify Desktop and Downloads are truly read-only
- macOS Docker Desktop file-sharing notes

The README should not lean on editor-specific tooling to explain the workflow. Path identity is enough.

## Implementation Order

### Phase 1. Lock the UX

- make `dclaude` and `dcodex` the only documented commands
- remove API-key auth from the design
- remove editor-specific helper assumptions

Success criteria:

- the plan, README, and scripts all describe the same entrypoints

### Phase 2. Build the image

- add `Dockerfile`
- install baseline Python and Node tooling
- install Claude Code and Codex at build time

Success criteria:

- image builds cleanly
- both CLIs are available in the image

### Phase 3. Implement `dclaude` and `dcodex`

- same-path repo mount
- same-path Desktop/Downloads mounts
- host UID/GID mapping
- `HOME` parity
- `/workspace` symlink
- per-tool auth mounts
- cache mounts

Success criteria:

- both commands start in the correct host-real path
- files created in the repo are owned by the host user

### Phase 4. Add optional GitHub SSH mode

- forward `SSH_AUTH_SOCK`
- mount `known_hosts` read-only if present
- keep raw private keys out of the container

Success criteria:

- GitHub SSH works in the container if it already works on the host

### Phase 5. Add Compose support

- add thin compose file
- keep it aligned with the scripts

Success criteria:

- compose path matches script behavior closely enough

### Phase 6. Write the README and validate end to end

- document the mount model
- document auth persistence
- document GitHub SSH mode
- document security boundaries

Success criteria:

- a new user can run the workflow and understand the risk model without reverse-engineering the scripts

## Acceptance Criteria

1. `dclaude` starts Claude Code in Docker from the current repo path.
2. `dcodex` starts Codex in Docker from the current repo path.
3. `pwd` inside the container matches the host repo path.
4. `echo ~` inside the container matches the host home path.
5. `/workspace` exists and resolves to the repo root.
6. edits made locally in the repo are visible instantly in the container.
7. edits made by the agent in the repo are visible instantly on the host.
8. `touch ~/Desktop/test` fails in the container.
9. `touch ~/Downloads/test` fails in the container.
10. writing inside the repo succeeds in the container.
11. repo files created by the container are owned by the host user.
12. Claude login persists across container restarts.
13. Codex login persists across container restarts.
14. no `docker.sock` mount exists.
15. optional GitHub SSH mode works without mounting raw private key files.
16. no API-key-based Claude/Codex auth path exists in the default or documented workflow.

## Risks

### 1. Same-path home semantics are unusual in Linux containers

Risk:

- some tools may expect a more conventional Linux home path

Response:

- start with path fidelity as the design goal
- validate both official CLIs explicitly
- add a compatibility shim only if a concrete tool actually breaks

### 2. Mounted auth state is reachable by the agent

Risk:

- a malicious repo can access mounted auth state

Response:

- keep the mount set narrow
- avoid full home mounts
- avoid `docker.sock`
- use this only on trusted repos

### 3. Forwarded SSH agents delegate live signing authority

Risk:

- the container can use whatever identities are loaded into the forwarded agent while it is running

Response:

- make GitHub SSH mode explicit and opt-in
- recommend a dedicated container-only GitHub key
- recommend a dedicated `ssh-agent`

### 4. Codex CLI flags can drift by release

Risk:

- full-access flags may change over time

Response:

- pin the installed CLI version
- validate against `codex --help` during implementation

## Recommended Final Shape

The final implementation should be:

- one shared Docker image
- `dclaude` and `dcodex` as the only user-facing commands
- optional one-file internal shared helper
- canonical same-path mounts for repo, Desktop, and Downloads
- narrow mounted auth state for Claude and Codex
- optional SSH agent forwarding for GitHub access
- host-real working directory
- `/workspace` as a compatibility alias only
- no API-key auth support
- no full-home mount
- no `docker.sock`
