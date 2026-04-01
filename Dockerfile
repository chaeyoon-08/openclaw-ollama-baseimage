# Dockerfile — openclaw-ollama base image
#
# References:
#   CUDA base image:  https://hub.docker.com/r/nvidia/cuda
#   CUDA release notes (driver compatibility): https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/
#   Ollama Linux install: https://docs.ollama.com/linux
#   OpenClaw install:     https://docs.openclaw.ai/install/docker
#   Node.js install:      https://github.com/nodesource/distributions
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

# === 기본 도구 설치 ===
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
    inotify-tools \
    && rm -rf /var/lib/apt/lists/*

# === Node.js 24 설치 ===
# Source: https://github.com/nodesource/distributions
# OpenClaw은 Node.js 22.16+ 필수, 24 권장
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# === Ollama 설치 ===
# Source: https://docs.ollama.com/linux
# tar 방식 사용: install.sh는 systemd 서비스까지 설치하므로 컨테이너에 부적합
# 파이프 스트림에서 tar의 zst 자동 감지가 불안정하므로 파일로 받은 뒤 명시적 해제
# → /usr/bin/ollama 에 바이너리, /usr/lib/ollama/ 에 GPU 라이브러리 설치됨
RUN curl -fsSL https://ollama.com/download/ollama-linux-amd64.tar.zst \
        -o /tmp/ollama.tar.zst \
    && zstd -d /tmp/ollama.tar.zst --stdout | tar x -C /usr \
    && rm /tmp/ollama.tar.zst

# === OpenClaw 설치 ===
# Source: https://docs.openclaw.ai/install/docker
RUN npm install -g openclaw@latest

# 작업 디렉터리 생성
RUN mkdir -p /root/.openclaw/workspace /workspace

EXPOSE 18789

COPY entrypoint.sh /entrypoint.sh
COPY backup-manager.sh /usr/local/bin/backup-manager.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/backup-manager.sh

WORKDIR /workspace

ENTRYPOINT ["/entrypoint.sh"]
