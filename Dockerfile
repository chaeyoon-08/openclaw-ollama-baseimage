# Dockerfile — openclaw-mcp-hub
#
# 역할: 외부 서비스 인증이 필요한 MCP 서버 전용 컨테이너.
#       OpenClaw(main 컨테이너)와 동일 Pod 내에서 localhost 통신.
#
# 포트:
#   3100 — notebooklm MCP SSE 엔드포인트 (main 컨테이너 → localhost:3100/sse)
#   6080 — noVNC 웹 인터페이스 (nlm login 재인증 시 브라우저 접근)
#
# References:
#   uv:                 https://docs.astral.sh/uv/
#   notebooklm-mcp-cli: https://github.com/jacob-bd/notebooklm-mcp-cli
#   supergateway:       https://github.com/supermaven-inc/supergateway
#   noVNC:              https://github.com/novnc/noVNC
#   Google Chrome deb:  https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Seoul

# uv 도구 경로
# UV_PYTHON_INSTALL_DIR: /root 대신 /opt에 설치 → 비root 실행 시 EACCES 방지
ENV UV_TOOL_DIR=/opt/uv/tools
ENV UV_TOOL_BIN_DIR=/usr/local/bin
ENV UV_CACHE_DIR=/opt/uv/cache
ENV UV_PYTHON_INSTALL_DIR=/opt/uv/python

# notebooklm MCP SSE 포트 (환경변수로 override 가능)
ENV NLM_MCP_PORT=3100

# === 기본 도구 ===
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    ca-certificates \
    python3 \
    python3-pip \
    jq \
    && rm -rf /var/lib/apt/lists/*

# === VNC 스택 (nlm login 재인증 시 noVNC 브라우저 접근용) ===
# x11vnc, novnc, python3-websockify: Ubuntu 22.04 universe 저장소에만 있음
# Source: https://launchpad.net/ubuntu/jammy/+package/x11vnc
RUN apt-get update && apt-get install -y --no-install-recommends software-properties-common \
    && add-apt-repository -y universe \
    && apt-get update && apt-get install -y --no-install-recommends \
        xvfb \
        x11vnc \
        python3-websockify \
        novnc \
        openbox \
    && rm -rf /var/lib/apt/lists/*

# === Google Chrome (nlm login 브라우저 인증 전용) ===
# Ubuntu 22.04에서 chromium-browser는 snap으로 전환되어 Docker에서 동작 불가.
# Google Chrome .deb 직접 설치로 우회.
# Source: https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
RUN wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get install -y /tmp/chrome.deb \
    && rm /tmp/chrome.deb \
    && rm -rf /var/lib/apt/lists/*

# === Node.js 24 (JS 기반 MCP 서버 확장 대비) ===
# Source: https://github.com/nodesource/distributions
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# === uv (Python 패키지 매니저) ===
# Source: https://docs.astral.sh/uv/getting-started/installation/
RUN pip3 install uv \
    && mkdir -p /opt/uv/tools /opt/uv/cache

# === notebooklm-mcp-cli ===
# --python 3.12: typing.TypedDict 호환성 이슈로 3.11 사용 불가
# Source: https://github.com/jacob-bd/notebooklm-mcp-cli
RUN uv tool install notebooklm-mcp-cli --python 3.12 \
    && chmod -R a+rX /opt/uv/

# === supergateway (stdio MCP → SSE/HTTP 변환 프록시) ===
# notebooklm-mcp-cli는 stdio 전용이므로 supergateway로 SSE 서버로 변환.
# main 컨테이너의 OpenClaw가 SSE URL로 연결 가능.
# Source: https://github.com/supermaven-inc/supergateway
RUN npm install -g supergateway

# === 스크립트 복사 ===
COPY entrypoint.sh /entrypoint.sh
COPY nlm-reauth-start.sh /usr/local/bin/nlm-reauth-start.sh
COPY nlm-reauth-finish.sh /usr/local/bin/nlm-reauth-finish.sh
RUN chmod +x \
    /entrypoint.sh \
    /usr/local/bin/nlm-reauth-start.sh \
    /usr/local/bin/nlm-reauth-finish.sh

EXPOSE 6080
EXPOSE 3100

ENTRYPOINT ["/entrypoint.sh"]
