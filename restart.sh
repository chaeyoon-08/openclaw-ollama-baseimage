#!/bin/bash
# restart.sh — OpenClaw gateway full restart
#
# 신규 Ollama 모델 추가 후 /api/tags 재스캔이 필요할 때 사용.
# reload.sh (SIGUSR1)는 모델 변경에 무효 — full restart 필요.
# entrypoint.sh while 루프가 게이트웨이 종료를 감지하고 자동 재시작한다.
#
# Source: https://github.com/openclaw/openclaw/issues/49568

log_warn()  { echo -e "\033[1;33m[ WARN  ]\033[0m $1"; }
log_ok()    { echo -e "\033[0;32m[  OK   ]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ ERROR ]\033[0m $1"; }
log_done()  { echo -e "\033[1;32m[ DONE  ]\033[0m $1"; }

OPENCLAW_PID=$(pgrep -u node -f "openclaw gateway" 2>/dev/null | head -1 || true)

if [ -z "$OPENCLAW_PID" ]; then
    log_error "No running gateway found. entrypoint.sh should restart it automatically."
    exit 1
fi

log_warn "Stopping gateway (PID: ${OPENCLAW_PID}) for full restart..."
kill "$OPENCLAW_PID"

sleep 1
log_ok "Gateway stopped. entrypoint.sh will restart it automatically."
log_done "Restart triggered. New Ollama models will be available after restart completes."
