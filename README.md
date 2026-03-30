# dclaude

`dclaude` and `dcodex` run Claude Code and Codex inside Docker without copying your repo into the container. The working tree is bind-mounted live, and the container sees the repo, `~/Desktop`, and `~/Downloads` at the same absolute paths you see on the host.

That path fidelity is the whole point:

- when the agent writes `/Users/.../plan.md`, that is the real file on the host
- when you paste `~/Desktop/image.png`, that path is real inside the container
- `/workspace` exists only as a compatibility alias

## Requirements

- Docker Desktop or Docker Engine with `docker` and `docker compose`
- a trusted repo
- existing `~/Desktop` and `~/Downloads` directories
- Docker Desktop file sharing enabled for the repo path, `~/Desktop`, and `~/Downloads` on macOS

## Quick Start

From the repo root:

```bash
./dclaude
./dcodex
```

From anywhere inside the repo, use the wrapper on `PATH`:

```bash
dclaude
dcodex
```

If you are not installing the wrappers on `PATH`, call the repo-root scripts explicitly.

The first run builds the shared image automatically. Subsequent runs reuse it unless you pass `--rebuild`.

Wrapper options:

- `--rebuild` forces a fresh `docker build`
- `--ssh` forwards `/run/host-services/ssh-auth.sock` and `~/.ssh/known_hosts` when available
- `--` passes the remaining arguments to the underlying CLI

Examples:

```bash
./dcodex -- --help
./dclaude --rebuild
./dcodex --ssh
```

## Runtime Model

Every launch does the following:

- bind-mounts the repo read/write at its real host path
- bind-mounts `~/Desktop` read-only at the same path
- bind-mounts `~/Downloads` read-only at the same path
- runs as the current host UID/GID
- sets `HOME` to the host home path
- starts in the current host working directory
- creates `/workspace` as a compatibility alias that resolves back to the repo root

This means `pwd` inside the container matches the host repo path, not `/workspace`.

## Auth Persistence

Auth state is mounted from the host. It is not copied into the image or into container-local state.

Claude mounts:

- `~/.claude`
- `~/.config/claude-code`

Codex mounts:

- `~/.codex`

Shared caches:

- `~/.cache/pip`
- `~/.cache/uv`

Interactive login happens through the official CLIs inside the container. If you are not logged in yet, run the wrapper and complete the normal login flow there. The mounted state keeps you logged in across container restarts.

API-key auth is intentionally unsupported for both tools. This repo does not provide `.env`-driven auth, `ANTHROPIC_API_KEY`, or `OPENAI_API_KEY` workflow guidance.

## Optional GitHub SSH Access

`--ssh` enables forwarded SSH agent access without copying raw private keys into the image.

When enabled, the wrappers mount:

- `/run/host-services/ssh-auth.sock`
- `~/.ssh/known_hosts` read-only when present

They do not mount the full `~/.ssh` directory and they never copy private key files into the container.

Recommended host checks before using `--ssh`:

```bash
ssh-add -L
ssh -T git@github.com
```

Recommended container checks after launching with `--ssh`:

```bash
echo "$SSH_AUTH_SOCK"
ssh-add -L
ssh -T git@github.com
```

Use a dedicated GitHub key loaded into a dedicated `ssh-agent` if you want a narrower blast radius.

## Compose

Compose is secondary. The wrappers are the primary interface.

To use Compose directly, provide the runtime variables explicitly:

```bash
HOST_HOME="$HOME" \
HOST_UID="$(id -u)" \
HOST_GID="$(id -g)" \
PROJECT_ROOT="$(git rev-parse --show-toplevel)" \
CURRENT_PATH="$PWD" \
docker compose run --rm dcodex
```

SSH-enabled compose services are available under the `ssh` profile:

```bash
HOST_HOME="$HOME" \
HOST_UID="$(id -u)" \
HOST_GID="$(id -g)" \
PROJECT_ROOT="$(git rev-parse --show-toplevel)" \
CURRENT_PATH="$PWD" \
COMPOSE_PROFILES=ssh \
docker compose run --rm dcodex-ssh
```

The compose file stays intentionally thin and mirrors the wrapper behavior. The wrappers remain the better default because they validate the host prerequisites and create the mounted state directories when needed.

## Rebuilds

Rebuild explicitly when you want updated pinned tool versions or image changes:

```bash
docker build -t dclaude:local .
./dclaude --rebuild
```

The image currently pins:

- `@anthropic-ai/claude-code@2.1.83`
- `@openai/codex@0.117.0`

The Codex full-access launcher was validated against `codex-cli 0.117.0`, which supports `--dangerously-bypass-approvals-and-sandbox`.

## Security Boundary

This setup is for trusted repos. Anything reachable inside the container is reachable by the agent.

Deliberately omitted:

- `docker.sock`
- `--privileged`
- full home-directory mounts
- full `~/.ssh` mounts
- copied SSH key files
- API-key auth shortcuts

Verify the Desktop and Downloads mounts are read-only with:

```bash
touch ~/Desktop/test
touch ~/Downloads/test
```

Both commands should fail inside the container. Writing in the repo should still succeed.
