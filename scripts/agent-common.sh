#!/usr/bin/env bash

set -euo pipefail

DCLAUDE_IMAGE_NAME="${DCLAUDE_IMAGE_NAME:-dclaude:local}"

die() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  local tool="$1"
  cat <<EOF
usage: ./$tool [--rebuild] [--ssh] [--] [tool args...]

Options:
  --rebuild  rebuild the Docker image before launching
  --ssh      forward the host SSH agent socket and known_hosts when available
  --help     show this wrapper help

Examples:
  ./$tool
  ./$tool -- --help
  ./$tool --ssh
EOF
}

ensure_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

ensure_docker() {
  ensure_command docker
  docker info >/dev/null 2>&1 || die "docker daemon is not available"
}

ensure_required_paths() {
  [ -d "$HOST_HOME/Desktop" ] || die "expected $HOST_HOME/Desktop to exist"
  [ -d "$HOST_HOME/Downloads" ] || die "expected $HOST_HOME/Downloads to exist"
}

ensure_host_state() {
  mkdir -p \
    "$HOST_HOME/.cache/pip" \
    "$HOST_HOME/.cache/uv" \
    "$HOST_HOME/.config"

  case "$1" in
    claude)
      mkdir -p "$HOST_HOME/.claude" "$HOST_HOME/.config/claude-code"
      ;;
    codex)
      mkdir -p "$HOST_HOME/.codex"
      ;;
    *)
      die "unsupported tool: $1"
      ;;
  esac
}

image_exists() {
  docker image inspect "$DCLAUDE_IMAGE_NAME" >/dev/null 2>&1
}

build_image() {
  echo "Building $DCLAUDE_IMAGE_NAME from $PROJECT_ROOT" >&2
  docker build -t "$DCLAUDE_IMAGE_NAME" "$PROJECT_ROOT"
}

parse_wrapper_args() {
  ENABLE_SSH=0
  REBUILD_IMAGE=0
  TOOL_ARGS=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --ssh)
        ENABLE_SSH=1
        ;;
      --rebuild)
        REBUILD_IMAGE=1
        ;;
      --help|-h)
        usage "$WRAPPER_NAME"
        exit 0
        ;;
      --)
        shift
        TOOL_ARGS=("$@")
        return 0
        ;;
      *)
        TOOL_ARGS+=("$1")
        ;;
    esac
    shift
  done
}

append_common_mounts() {
  DOCKER_ARGS+=(
    --mount "type=bind,src=$PROJECT_ROOT,dst=$PROJECT_ROOT"
    --mount "type=bind,src=$HOST_HOME/Desktop,dst=$HOST_HOME/Desktop,readonly"
    --mount "type=bind,src=$HOST_HOME/Downloads,dst=$HOST_HOME/Downloads,readonly"
    --mount "type=bind,src=$HOST_HOME/.cache/pip,dst=$HOST_HOME/.cache/pip"
    --mount "type=bind,src=$HOST_HOME/.cache/uv,dst=$HOST_HOME/.cache/uv"
  )
}

append_tool_mounts() {
  case "$1" in
    claude)
      DOCKER_ARGS+=(
        --mount "type=bind,src=$HOST_HOME/.claude,dst=$HOST_HOME/.claude"
        --mount "type=bind,src=$HOST_HOME/.config/claude-code,dst=$HOST_HOME/.config/claude-code"
      )
      ;;
    codex)
      DOCKER_ARGS+=(
        --mount "type=bind,src=$HOST_HOME/.codex,dst=$HOST_HOME/.codex"
      )
      ;;
    *)
      die "unsupported tool: $1"
      ;;
  esac
}

append_ssh_mounts() {
  local ssh_socket="/run/host-services/ssh-auth.sock"
  local known_hosts="$HOST_HOME/.ssh/known_hosts"

  [ -S "$ssh_socket" ] || die "SSH forwarding requested but $ssh_socket is not available"

  DOCKER_ARGS+=(
    --mount "type=bind,src=$ssh_socket,dst=$ssh_socket"
    -e "SSH_AUTH_SOCK=$ssh_socket"
  )

  if [ -f "$known_hosts" ]; then
    mkdir -p "$HOST_HOME/.ssh"
    DOCKER_ARGS+=(
      --mount "type=bind,src=$known_hosts,dst=$known_hosts,readonly"
    )
  fi
}

append_common_env() {
  DOCKER_ARGS+=(
    -e "HOME=$HOST_HOME"
    -e "PIP_CACHE_DIR=$HOST_HOME/.cache/pip"
    -e "UV_CACHE_DIR=$HOST_HOME/.cache/uv"
    -e "PROJECT_ROOT=$PROJECT_ROOT"
    -e "TERM=${TERM:-xterm-256color}"
    -e "COLORTERM=${COLORTERM:-truecolor}"
  )
}

append_tool_env() {
  case "$1" in
    claude)
      DOCKER_ARGS+=(-e "DISABLE_AUTOUPDATER=1")
      ;;
    codex)
      DOCKER_ARGS+=(-e "CODEX_HOME=$HOST_HOME/.codex")
      ;;
    *)
      die "unsupported tool: $1"
      ;;
  esac
}

append_launch_command() {
  local tool="$1"
  case "$tool" in
    claude)
      LAUNCH_CMD=(claude --dangerously-skip-permissions)
      ;;
    codex)
      LAUNCH_CMD=(codex --dangerously-bypass-approvals-and-sandbox)
      ;;
    *)
      die "unsupported tool: $tool"
      ;;
  esac

  if [ "${#TOOL_ARGS[@]}" -gt 0 ]; then
    LAUNCH_CMD+=("${TOOL_ARGS[@]}")
  fi
}

launch_agent() {
  local tool="$1"
  shift

  WRAPPER_NAME="d${tool}"
  parse_wrapper_args "$@"

  PROJECT_ROOT="$(cd "$(git rev-parse --show-toplevel)" && pwd -P)"
  CURRENT_PATH="$(pwd -P)"
  HOST_HOME="$(cd "$HOME" && pwd -P)"
  HOST_UID="$(id -u)"
  HOST_GID="$(id -g)"

  ensure_docker
  ensure_required_paths
  ensure_host_state "$tool"

  if [ "$REBUILD_IMAGE" -eq 1 ] || ! image_exists; then
    build_image
  fi

  DOCKER_ARGS=(
    run
    --rm
    --init
    --workdir "$CURRENT_PATH"
    --user "$HOST_UID:$HOST_GID"
    --cap-drop=ALL
    --security-opt no-new-privileges:true
  )

  if [ -t 0 ] && [ -t 1 ]; then
    DOCKER_ARGS+=(-it)
  else
    DOCKER_ARGS+=(-i)
  fi

  append_common_mounts
  append_tool_mounts "$tool"
  append_common_env
  append_tool_env "$tool"

  if [ "$ENABLE_SSH" -eq 1 ]; then
    append_ssh_mounts
  fi

  append_launch_command "$tool"

  exec docker "${DOCKER_ARGS[@]}" \
    "$DCLAUDE_IMAGE_NAME" \
    /bin/bash -lc 'ln -sfn "$PROJECT_ROOT" /var/run/dclaude/workspace && exec "$@"' \
    bash \
    "${LAUNCH_CMD[@]}"
}
