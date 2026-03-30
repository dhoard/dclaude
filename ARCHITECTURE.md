# Architecture

## Overview

This repo provides a Dockerized wrapper around the official Claude Code and Codex CLIs. The project is intentionally small:

- one shared Docker image
- two user-facing entrypoints: `dclaude` and `dcodex`
- one shared shell helper for runtime assembly
- one thin `docker-compose.yml` for parity, not as the primary UX

The design goal is path fidelity. The repo, `~/Desktop`, and `~/Downloads` are mounted into the container at the same absolute paths they have on the host. `/workspace` exists only as a compatibility alias.

## Components

### `Dockerfile`

Builds the shared runtime image on top of `python:3.12-slim`, installs Node 22, `uv`, and the official CLI packages:

- `@anthropic-ai/claude-code@2.1.83`
- `@openai/codex@0.117.0`

The image also pre-creates `/workspace` as an alias chain that can be repointed at runtime without root privileges.

### `dclaude` and `dcodex`

Thin wrappers that:

- require Docker
- resolve the git repo root and current path
- create minimal host state directories
- mount the repo and support paths with same-path bind mounts
- run the container as the current host UID/GID
- launch the correct interactive CLI command

### `scripts/agent-common.sh`

Holds the shared launch logic:

- common Docker flags
- mount assembly
- optional SSH agent forwarding
- image build bootstrap
- `/workspace` compatibility alias setup

### `docker-compose.yml`

Mirrors the wrapper runtime model for manual use. It is intentionally secondary and requires explicit environment variables.

## Runtime Mount Model

Always mounted:

- repo root at its real host path, read/write
- `~/Desktop` at the same path, read-only
- `~/Downloads` at the same path, read-only
- `~/.cache/pip`
- `~/.cache/uv`

Claude-only state:

- `~/.claude`
- `~/.config/claude-code`

Codex-only state:

- `~/.codex`

Optional SSH mode:

- `/run/host-services/ssh-auth.sock`
- `~/.ssh/known_hosts` read-only

## Process Model

The wrappers launch Docker with:

- `--rm`
- `--init`
- `--cap-drop=ALL`
- `--security-opt=no-new-privileges:true`
- `--user <host uid>:<host gid>`
- `--workdir <current host path>`

Tool launch commands:

- Claude: `claude --dangerously-skip-permissions`
- Codex: `codex --dangerously-bypass-approvals-and-sandbox`

## Persistent State

This repo has no application database. Persistence consists only of host-mounted auth and cache directories.

### Database Schema

None.

There are no tables, collections, migrations, or ORM models in this project. The only stateful paths are filesystem mounts:

- Claude auth/config: `~/.claude`, `~/.config/claude-code`
- Codex state: `~/.codex`
- shared caches: `~/.cache/pip`, `~/.cache/uv`

## Security Notes

The sandbox boundary is Docker plus the narrow mount set. The design explicitly excludes:

- `docker.sock`
- privileged mode
- full home-directory mounts
- raw private key file mounts
- API-key auth workflows for Claude or Codex
