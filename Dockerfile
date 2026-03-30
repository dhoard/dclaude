# syntax=docker/dockerfile:1

FROM python:3.12-slim

ARG NODE_MAJOR=22
ARG CLAUDE_CODE_VERSION=2.1.83
ARG CODEX_VERSION=0.117.0

ENV DEBIAN_FRONTEND=noninteractive
ENV DISABLE_AUTOUPDATER=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        build-essential \
        ca-certificates \
        coreutils \
        curl \
        fd-find \
        git \
        gnupg \
        jq \
        openssh-client \
        procps \
        ripgrep \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "@openai/codex@${CODEX_VERSION}" \
    && pip install --no-cache-dir uv \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && mkdir -p /var/run/dclaude \
    && chmod 1777 /var/run/dclaude \
    && ln -s /var/run/dclaude/workspace /workspace \
    && rm -rf /var/lib/apt/lists/* /root/.npm /tmp/*
