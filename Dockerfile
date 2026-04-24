# Dockerfile — openclaw multi-agent base image
#
# References:
#   CUDA base image:         https://hub.docker.com/r/nvidia/cuda
#   CUDA release notes:      https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/
#   Ollama Linux install:    https://docs.ollama.com/linux
#   OpenClaw install:        https://docs.openclaw.ai/install/docker
#   Node.js install:         https://github.com/nodesource/distributions
#   gosu (user switch):      https://github.com/tianon/gosu
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

# OpenClaw Ollama auto-discovery 인증 키
# models.providers.ollama 블록 미정의 시 이 값으로 /api/tags 자동 스캔 활성화
# Source: https://docs.openclaw.ai/providers/ollama
ENV OLLAMA_API_KEY=ollama-local

# Ollama VRAM 최적화
# KV_CACHE_TYPE=q8_0: KV 캐시 8-bit 양자화 → VRAM 절반 절감 (품질 손실 거의 없음)
# MAX_LOADED_MODELS=2: primary 모델(1) + 전환 버퍼(1) 동시 VRAM 상주
#   사용자가 /models로 모델 전환 시 이전 모델이 즉시 unload되지 않도록 여유 확보
#   현재 구조는 single primary 운영이 기본이나, 전환 UX 위해 2 유지
ENV OLLAMA_KV_CACHE_TYPE=q8_0
ENV OLLAMA_MAX_LOADED_MODELS=2

# Context window 제어 (OpenClaw의 openclaw.json contextWindow가 최종 적용)
# 실측 결과 (2026-04-24): OpenClaw는 기동 시 GGUF 메타데이터의 context_length를 읽어
#   num_ctx로 전달하며, 아래 OLLAMA_* 환경변수는 오버라이드하지 못함.
#   openclaw.json의 models.providers.ollama.models[].contextWindow가 유일한 제어점.
#   → generate-config.sh가 DEFAULT_CONTEXT_WINDOW 기반으로 각 모델에 contextWindow 삽입.
# Source: OpenClaw 공식 문서 (providers/ollama) — contextWindow 필드 권장
# Source: 내부 검증 — https://github.com/openclaw/openclaw/issues/44550
ENV DEFAULT_CONTEXT_WINDOW=65536
ENV DEFAULT_MAX_TOKENS=8192

# 구 환경변수 (효과 없음 확인됨, 참조용 주석 유지)
# OLLAMA_NUM_CTX_ORCH, OLLAMA_CONTEXT_LENGTH는 OpenClaw가 GGUF 메타를 우선하여 무시됨.
# 향후 Ollama 또는 OpenClaw 업데이트로 동작이 바뀔 수 있어 env 자체는 보존.
ENV OLLAMA_NUM_CTX_ORCH=65536
ENV OLLAMA_CONTEXT_LENGTH=65536

# 시간대 설정
ENV TZ=Asia/Seoul

# === 기본 도구 설치 ===
# apt 미러: archive.ubuntu.com → mirrors.edge.kernel.org/ubuntu
#   근거: GitHub Actions Docker 빌드 환경에서 archive.ubuntu.com 반복 연결 실패
#         (exit code: 100, Connection failed [IP: 185.125.190.82 80])
#         mirrors.edge.kernel.org는 Linux Foundation 운영, CDN 배포, 전역 안정성 높음
# gosu: entrypoint에서 root → node 전환으로 openclaw gateway를 비root 실행
# Source: https://github.com/tianon/gosu
# Source: https://mirrors.edge.kernel.org/ubuntu/
RUN sed -i \
        -e 's|http://archive.ubuntu.com/ubuntu|https://mirrors.edge.kernel.org/ubuntu|g' \
        -e 's|http://security.ubuntu.com/ubuntu|https://mirrors.edge.kernel.org/ubuntu|g' \
        /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends \
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
        iproute2 \
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

# === OpenClaw 설치 ===
# Source: https://docs.openclaw.ai/install/docker
# root로 시스템 전역 설치 → /usr/local/bin/openclaw (node 사용자도 gosu로 실행 가능)
# 2026.4.15 (2026-04-16 stable): Ollama provider 회귀(#66202) 수정 완료
#   - ollama/ prefix를 chat 요청 시 자동 strip (ollama/qwen3:14b → qwen3:14b)
#   - embedded-run timeout → undici stream timeout 전달 (대형 모델 타임아웃 방지)
#   - Ollama 스트리밍 응답에 usage 정보 포함
#   - compaction reserve-token floor cap (16K 모델 무한 루프 방지, Issue #65671)
# 2026.4.19-beta.x: subagent channel routing 수정 포함 (아직 stable 아님 — 대기)
# Source: https://github.com/openclaw/openclaw/issues/66202
RUN npm install -g openclaw@2026.4.15

# === 디렉터리 생성 및 권한 설정 ===
# /home/node/.openclaw  : OpenClaw 설정·세션·메모리 (gcube OpenClaw_Data 마운트 대상)
# /root/.ollama         : Ollama 모델 저장소 (gcube Ollama_Models 마운트 대상)
# /workspace            : GitHub repo 클론 대상
RUN mkdir -p \
        /home/node/.openclaw/workspace \
        /root/.ollama \
        /workspace \
    && chown -R node:node /home/node

# === 스크립트 및 템플릿 복사 ===
# reload.sh: .env 변경 후 generate-config.sh 재실행 + gateway SIGUSR1 in-process reload
# restart.sh: Ollama 모델 추가 후 /api/tags 재스캔이 필요할 때 gateway full restart
#   (두 스크립트는 사용자가 대화로 모델 추가 요청 시 에이전트가 shell로 호출하거나,
#    사용자가 직접 Control UI/SSH로 실행하는 용도)
COPY templates/ /templates/
COPY entrypoint.sh /entrypoint.sh
COPY generate-config.sh /usr/local/bin/generate-config.sh
COPY reload.sh /usr/local/bin/reload.sh
COPY restart.sh /usr/local/bin/restart.sh
RUN chmod +x /entrypoint.sh \
    /usr/local/bin/generate-config.sh \
    /usr/local/bin/reload.sh \
    /usr/local/bin/restart.sh

EXPOSE 18789

WORKDIR /workspace

ENTRYPOINT ["/entrypoint.sh"]