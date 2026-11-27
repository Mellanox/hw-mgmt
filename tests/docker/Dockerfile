# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause
#
# Test environment for tests/test.py. The source tree is NOT copied into the
# image: run-tests.sh bind-mounts it at its host path, so the image only changes
# when tests/requirements.txt or this file changes.
#
# Build context is tests/ (see run-tests.sh); only requirements.txt is used.

FROM debian:trixie-slim

ARG SHELLSPEC_VERSION=0.28.1

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:/usr/local/bin:/usr/bin:/bin

# bash/jq/gawk/procps/xz-utils: used by the BMC and shell validation scripts.
# kcov/shellcheck: shell coverage and static analysis (--shell-coverage, --shellcheck).
# docker-cli: ngci_tool.sh starts its checkers with "docker run" (run-tests.sh --ngci
# gives it the host Docker socket).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        coreutils \
        docker-cli \
        gawk \
        git \
        jq \
        kcov \
        procps \
        python3 \
        python3-pip \
        python3-venv \
        shellcheck \
        sshpass \
        openssh-client \
        xz-utils \
    && git clone --depth 1 --branch "${SHELLSPEC_VERSION}" \
        https://github.com/shellspec/shellspec.git /tmp/shellspec \
    && /tmp/shellspec/install.sh --yes --prefix /usr/local \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/shellspec

# Python deps live in a venv so pip does not hit the PEP 668 restriction and
# test.py's own dependency check finds everything already installed.
COPY requirements.txt /tmp/requirements.txt
RUN python3 -m venv "${VIRTUAL_ENV}" \
    && pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

WORKDIR /workspace

# Fallback for a manual "docker run -v <repo>:/workspace"; run-tests.sh overrides it.
CMD ["python3", "/workspace/tests/test.py", "--offline", "--skip-ngci"]
