# Dockerfile — openclaw multi-agent base image
#
# References:
#   CUDA base image:         https://hub.docker.com/r/nvidia/cuda
#   CUDA release notes:      https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/
#   Ollama Linux install:    https://docs.ollama.com/linux
#   OpenClaw install:        https://docs.openclaw.ai/install/docker
#   Node.js install:         https://github.com/nodesource/distributions
#   gosu (user switch):      https://github.com/tianon/gosu
#   uv (Python pkg mgr):     https://docs.astral.sh/uv/
#   notebooklm-mcp-cli:      https://github.com/jacob-bd/notebooklm-mcp-cli
#
# Base: nvidia/cuda:12.8.1-runtime-ubuntu22.04
#   - CUDA 12.8.1: Pascal(sm_60) ~ Blackwell(sm_120) 전 GPU 지원 (CUDA 13.x부터 Pascal dropped)
#   - runtime 변형: Ollama는 사전 컴파일 바이너리라 devel 불필요
#   - Ubuntu 22.04 LTS: 2027년까지 지원
#   - 최소 호스트 드라이버: >= 570.124.06

FROM nvidia/cuda:12.8.1-runtime-ubuntu22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# NVIDIA GPU passthrough (Ollama GPU 감지에 필요)
# Source: https://github.com/ollama/ollama/blob/main/Dockerfile
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Ollama bind address (컨테이너 내부 전용)
ENV OLLAMA_HOST=127.0.0.1:11434

# 시간대 설정
ENV TZ=Asia/Seoul

# uv 도구 경로 설정 (notebooklm-mcp-cli 설치 및 실행에 필요)
# Source: https://docs.astral.sh/uv/concepts/tools/
# UV_PYTHON_INSTALL_DIR: 미설정 시 /root/.local/share/uv/python/ 에 설치되어
# node 사용자가 /root 접근 불가 → spawn EACCES 발생. /opt/uv/python 으로 고정.
ENV UV_TOOL_DIR=/opt/uv/tools
ENV UV_TOOL_BIN_DIR=/usr/local/bin
ENV UV_CACHE_DIR=/opt/uv/cache
ENV UV_PYTHON_INSTALL_DIR=/opt/uv/python

# === 기본 도구 설치 (gosu 포함) ===
# gosu: entrypoint에서 root → node 전환으로 openclaw gateway를 비root 실행
# Source: https://github.com/tianon/gosu
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    nano \
    vim \
    ca-certificates \
    build-essential \
    python3 \
    python3-pip \
    jq \
    zstd \
    gosu \
    && rm -rf /var/lib/apt/lists/*

# === Node.js 24 설치 ===
# Source: https://github.com/nodesource/distributions
# OpenClaw은 Node.js 22.16+ 필수, 24 권장
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# === node 사용자 생성 ===
# OpenClaw gateway를 비root로 실행하기 위한 전용 사용자 (uid=1000)
RUN useradd -m -u 1000 -s /bin/bash node

# === Ollama 설치 ===
# Source: https://docs.ollama.com/linux
# tar 방식: install.sh는 systemd 서비스까지 설치하므로 컨테이너에 부적합
# 파이프 스트림에서 tar의 zst 자동 감지가 불안정하므로 파일로 받은 뒤 명시적 해제
# 캐시 무효화용 ARG: 버전 업데이트 시 이 레이어부터 재빌드
ARG OLLAMA_VERSION=latest
RUN curl -fsSL https://ollama.com/download/ollama-linux-amd64.tar.zst \
        -o /tmp/ollama.tar.zst \
    && zstd -d /tmp/ollama.tar.zst --stdout | tar x -C /usr \
    && rm /tmp/ollama.tar.zst

# === uv 설치 ===
# Source: https://docs.astral.sh/uv/getting-started/installation/
# pip3로 설치 시 /usr/local/bin/uv, /usr/local/bin/uvx 위치 → node 사용자도 실행 가능
RUN pip3 install uv \
    && mkdir -p /opt/uv/tools /opt/uv/cache

# === notebooklm-mcp-cli 설치 ===
# Source: https://github.com/jacob-bd/notebooklm-mcp-cli
# UV_TOOL_DIR=/opt/uv/tools 에 격리된 venv로 설치
# UV_TOOL_BIN_DIR=/usr/local/bin 이므로 entry point가 시스템 PATH에 포함됨
# a+rX: node 사용자가 uvx notebooklm-mcp-cli 실행 가능하도록 읽기/실행 권한 부여
RUN uv tool install notebooklm-mcp-cli \
    && chmod -R a+rX /opt/uv/

# === OpenClaw 설치 ===
# Source: https://docs.openclaw.ai/install/docker
# root로 시스템 전역 설치 → /usr/local/bin/openclaw (node 사용자도 gosu로 실행 가능)
RUN npm install -g openclaw@latest

# === 디렉터리 생성 및 권한 설정 ===
# /home/node/.openclaw  : OpenClaw 설정·세션·메모리 (Dropbox OpenClaw_Data 마운트 대상)
# /home/node/.notebooklm: notebooklm-mcp-cli 기본 인증 경로 (fallback)
# /mnt/notebooklm       : Dropbox OpenClaw_Auth 마운트 대상 (NOTEBOOKLM_HOME 기본값)
# /workspace            : GitHub repo 클론 대상
RUN mkdir -p \
        /home/node/.openclaw/workspace \
        /home/node/.notebooklm \
        /mnt/notebooklm \
        /workspace \
    && chown -R node:node /home/node

# === 스크립트 및 템플릿 복사 ===
COPY templates/ /templates/
COPY entrypoint.sh /entrypoint.sh
COPY generate-config.sh /usr/local/bin/generate-config.sh
COPY reload.sh /usr/local/bin/reload.sh
RUN chmod +x /entrypoint.sh \
    /usr/local/bin/generate-config.sh \
    /usr/local/bin/reload.sh

EXPOSE 18789

WORKDIR /workspace

ENTRYPOINT ["/entrypoint.sh"]
