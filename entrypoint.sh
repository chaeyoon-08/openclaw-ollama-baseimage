#!/bin/bash
# entrypoint.sh — openclaw-mcp-hub 컨테이너 진입점
#
# 역할: 외부 서비스 인증이 필요한 MCP 서버들을 SSE 서버로 기동.
#       OpenClaw(main 컨테이너)와 동일 Pod 내 localhost 통신.
#
# 기동 순서:
#   1. NotebookLM 인증 경로 심링크 (gcube 볼륨 → ~/.notebooklm-mcp-cli)
#   2. notebooklm MCP 서버 SSE 기동 (supergateway, 포트 3100)
#
# 재인증 필요 시:
#   bash /usr/local/bin/nlm-reauth-start.sh  → noVNC(6080) + nlm login 기동
#   bash /usr/local/bin/nlm-reauth-finish.sh → 인증 파일 저장 + noVNC 정리
#
# References:
#   notebooklm-mcp-cli: https://github.com/jacob-bd/notebooklm-mcp-cli
#   supergateway:       https://github.com/supercorp-ai/supergateway

set -e

log_start() { echo -e "\033[1;34m[ START ]\033[0m $1"; }
log_doing() { echo -e "\033[0;36m[ DOING ]\033[0m $1"; }
log_ok()    { echo -e "\033[0;32m[  OK   ]\033[0m $1"; }
log_warn()  { echo -e "\033[1;33m[ WARN  ]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ ERROR ]\033[0m $1"; }
log_done()  { echo -e "\033[1;32m[ DONE  ]\033[0m $1"; }

# ── 1. NotebookLM 인증 경로 심링크 ──────────────────────────────────────────
# nlm login CLI는 ~/.notebooklm-mcp-cli/ 에 고정 저장.
# gcube 볼륨 경로로 심링크하여 컨테이너 재시작 후에도 인증 유지.
# Source: https://github.com/jacob-bd/notebooklm-mcp-cli/blob/main/docs/AUTHENTICATION.md
log_start "Setting up NotebookLM auth path"
NLM_HOME="${NOTEBOOKLM_MCP_CLI_PATH:-/mnt/notebooklm/OpenClaw_Auth}"
rm -rf /root/.notebooklm-mcp-cli
ln -s "$NLM_HOME" /root/.notebooklm-mcp-cli

if [ -L /root/.notebooklm-mcp-cli ]; then
    log_ok "NOTEBOOKLM_MCP_CLI_PATH: $NLM_HOME (symlinked)"
else
    log_warn "Symlink failed — auth may not persist across restarts"
fi

# ── 2. notebooklm MCP 서버 (SSE 모드) ───────────────────────────────────────
# supergateway: stdio MCP 서버를 SSE/HTTP로 변환
# OpenClaw(main) → http://localhost:3100/sse 로 연결
# Source: https://github.com/supercorp-ai/supergateway
log_start "Starting NotebookLM MCP server"
log_doing "Launching supergateway (SSE port: ${NLM_MCP_PORT:-3100})..."

supergateway \
    --stdio "uvx notebooklm-mcp-cli" \
    --port "${NLM_MCP_PORT:-3100}" \
    --baseUrl "http://localhost:${NLM_MCP_PORT:-3100}" \
    --ssePath /sse \
    --messagePath /message \
    > /tmp/nlm-mcp.log 2>&1 &
NLM_MCP_PID=$!

sleep 2
if ! kill -0 "$NLM_MCP_PID" 2>/dev/null; then
    log_error "NotebookLM MCP server failed to start. Log:"
    cat /tmp/nlm-mcp.log 2>/dev/null
    exit 1
fi
log_ok "NotebookLM MCP ready (PID: $NLM_MCP_PID)"

# ── 완료 ────────────────────────────────────────────────────────────────────
log_done "MCP hub started"
echo ""
echo "  NotebookLM MCP : http://localhost:${NLM_MCP_PORT:-3100}/sse"
echo "  noVNC (auth)   : port 6080 (run nlm-reauth-start.sh when needed)"
echo ""

# 메인 프로세스 유지 — MCP 서버 종료 시 컨테이너도 종료
_stop() {
    log_warn "Shutting down..."
    kill "$NLM_MCP_PID" 2>/dev/null
    exit 0
}
trap _stop SIGTERM SIGINT

wait $NLM_MCP_PID
