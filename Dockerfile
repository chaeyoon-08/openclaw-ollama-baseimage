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
#   noVNC (web VNC):         https://github.com/novnc/noVNC
#   Playwright install:      https://playwright.dev/python/docs/browsers
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

# Playwright 브라우저 경로: 시스템 전역 위치로 고정
# node 사용자도 접근 가능하도록 /opt/playwright-browsers 에 설치
# Source: https://playwright.dev/python/docs/browsers#managing-browser-binaries
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers

# === 기본 도구 + VNC 패키지 통합 설치 ===
# apt 미러: archive.ubuntu.com → mirrors.edge.kernel.org/ubuntu
#   근거: GitHub Actions Docker 빌드 환경에서 archive.ubuntu.com 반복 연결 실패
#         (exit code: 100, Connection failed [IP: 185.125.190.82 80])
#         mirrors.edge.kernel.org는 Linux Foundation 운영, CDN 배포, 전역 안정성 높음
# universe 저장소: x11vnc, openbox 설치에 필요
# apt-get update 1회 통합 (software-properties-common + add-apt-repository 불필요)
# gosu: entrypoint에서 root → node 전환으로 openclaw gateway를 비root 실행
# Source: https://github.com/tianon/gosu
# Source: https://launchpad.net/ubuntu/jammy/+package/x11vnc
# Source: https://mirrors.edge.kernel.org/ubuntu/
RUN sed -i \
        -e 's|http://archive.ubuntu.com/ubuntu|https://mirrors.edge.kernel.org/ubuntu|g' \
        -e 's|http://security.ubuntu.com/ubuntu|https://mirrors.edge.kernel.org/ubuntu|g' \
        /etc/apt/sources.list \
    && printf 'deb https://mirrors.edge.kernel.org/ubuntu jammy universe\ndeb https://mirrors.edge.kernel.org/ubuntu jammy-updates universe\ndeb https://mirrors.edge.kernel.org/ubuntu jammy-security universe\n' \
        > /etc/apt/sources.list.d/universe.list \
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
        xvfb \
        x11vnc \
        openbox \
    && rm -rf /var/lib/apt/lists/*

# === websockify + noVNC 설치 (apt 패키지 의존성 충돌 우회) ===
# websockify: pip3 설치 (python3-pip는 기본 도구 레이어에서 설치됨)
# noVNC v1.6.0: GitHub release 직설치 → /usr/share/novnc
# nlm-reauth-start.sh이 websockify --web /usr/share/novnc 경로를 직접 참조
# Source: https://github.com/novnc/noVNC/releases/tag/v1.6.0
RUN pip3 install websockify \
    && mkdir -p /usr/share/novnc \
    && curl -fsSL https://github.com/novnc/noVNC/archive/refs/tags/v1.6.0.tar.gz \
        | tar -xz --strip-components=1 -C /usr/share/novnc

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
RUN uv tool install notebooklm-mcp-cli --python 3.12 \
    && chmod -R a+rX /opt/uv/

# === Playwright Chromium 설치 (nlm-login 스킬 headful 모드용) ===
# notebooklm-mcp-cli venv의 playwright 바이너리를 find로 동적 탐색
# (uv 패키지명 정규화가 버전별로 다르므로 경로를 하드코딩하지 않음)
# --with-deps: Chromium 실행에 필요한 OS 패키지(libX11, libatk 등) 자동 설치
# Source: https://playwright.dev/python/docs/browsers#install-browsers
RUN _PW=$(find /opt/uv/tools -name "playwright" -path "*/bin/playwright" 2>/dev/null | head -1) \
    && if [ -z "$_PW" ]; then \
           echo "playwright binary not found in uv tools, falling back to pip3 install"; \
           pip3 install playwright; \
           _PW=playwright; \
       fi \
    && "$_PW" install chromium --with-deps \
    && chmod -R a+rX /opt/playwright-browsers

# === OpenClaw 설치 ===
# Source: https://docs.openclaw.ai/install/docker
# root로 시스템 전역 설치 → /usr/local/bin/openclaw (node 사용자도 gosu로 실행 가능)
# 2026.4.15 (2026-04-16 stable): Ollama provider 회귀(#66202) 수정 완료
#   - ollama/ prefix를 chat 요청 시 자동 strip (ollama/qwen3:14b → qwen3:14b)
#   - embedded-run timeout → undici stream timeout 전달 (대형 모델 타임아웃 방지)
#   - Ollama 스트리밍 응답에 usage 정보 포함
# 2026.4.19-beta.x: subagent channel routing 수정 포함 (아직 stable 아님 — 대기)
# Source: https://github.com/openclaw/openclaw/issues/66202
RUN npm install -g openclaw@2026.4.15

# === shell MCP 서버 설치 ===
# Source: https://github.com/mako10k/mcp-shell-server
# node 사용자 권한으로 ollama CLI, reload.sh 등 시스템 명령 실행 가능하게 함
# 이미지 사전 설치로 npx -y 다운로드 지연 없이 즉시 기동
RUN npm install -g @mako10k/mcp-shell-server

# === 디렉터리 생성 및 권한 설정 ===
# /home/node/.openclaw  : OpenClaw 설정·세션·메모리 (gcube OpenClaw_Data 마운트 대상)
# /home/node/.notebooklm: notebooklm-mcp-cli 기본 인증 경로 (fallback)
# /mnt/notebooklm       : gcube OpenClaw_Auth 마운트 대상 (NOTEBOOKLM_HOME 기본값)
# /root/.ollama         : Ollama 모델 저장소 (gcube Ollama_Models/ 마운트 대상)
# /workspace            : GitHub repo 클론 대상
RUN mkdir -p \
        /home/node/.openclaw/workspace \
        /home/node/.notebooklm \
        /mnt/notebooklm \
        /root/.ollama \
        /workspace \
    && chown -R node:node /home/node

# === 스크립트 및 템플릿 복사 ===
COPY templates/ /templates/
COPY entrypoint.sh /entrypoint.sh
COPY generate-config.sh /usr/local/bin/generate-config.sh
COPY reload.sh /usr/local/bin/reload.sh
COPY restart.sh /usr/local/bin/restart.sh
COPY nlm-reauth-start.sh /usr/local/bin/nlm-reauth-start.sh
COPY nlm-reauth-finish.sh /usr/local/bin/nlm-reauth-finish.sh
RUN chmod +x /entrypoint.sh \
    /usr/local/bin/generate-config.sh \
    /usr/local/bin/reload.sh \
    /usr/local/bin/restart.sh \
    /usr/local/bin/nlm-reauth-start.sh \
    /usr/local/bin/nlm-reauth-finish.sh

EXPOSE 18789
EXPOSE 6080

WORKDIR /workspace

ENTRYPOINT ["/entrypoint.sh"]
