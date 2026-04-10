#!/bin/bash
# reload.sh -- .env 변경 후 openclaw.json 재생성 + gateway 재시작
#
# 사용법: bash /usr/local/bin/reload.sh
#
# 동작:
#   1. /root/.openclaw/.env 를 읽어서 openclaw.json 재생성
#   2. openclaw gateway 프로세스 종료 (entrypoint.sh가 자동 재시작)
#
# References:
#   OpenClaw config: https://docs.openclaw.ai/gateway/configuration-reference

set -e

# -- 로그 함수 --
log_start()  { echo -e "\033[1;34m[ START ]\033[0m $1"; }
log_ok()     { echo -e "\033[0;32m[  OK   ]\033[0m $1"; }
log_warn()   { echo -e "\033[1;33m[ WARN  ]\033[0m $1"; }
log_error()  { echo -e "\033[0;31m[ ERROR ]\033[0m $1"; }
log_done()   { echo -e "\033[1;32m[ DONE  ]\033[0m $1"; }

ENV_FILE="/home/node/.openclaw/.env"

log_start "Reloading OpenClaw configuration"

# -- .env 존재 확인 --
if [ ! -f "$ENV_FILE" ]; then
    log_error ".env file not found: ${ENV_FILE}"
    log_error "Create .env first, then run this script again."
    exit 1
fi

# -- openclaw.json 재생성 --
bash /usr/local/bin/generate-config.sh
if [ $? -ne 0 ]; then
    log_error "Config generation failed. Gateway not restarted."
    exit 1
fi

# -- gateway 재시작 --
# entrypoint.sh의 while 루프가 gateway 종료를 감지하고 자동 재시작함
log_warn "Stopping OpenClaw gateway (auto-restart in ~3s)..."
pkill -f "openclaw gateway" 2>/dev/null || true

sleep 2

# gateway가 다시 올라왔는지 확인
RETRY=0
while [ $RETRY -lt 10 ]; do
    if pgrep -f "openclaw gateway" > /dev/null 2>&1; then
        log_ok "Gateway restarted successfully"
        log_done "Reload complete. New configuration is active."
        exit 0
    fi
    sleep 1
    RETRY=$((RETRY + 1))
done

log_warn "Gateway may still be restarting. Check with: pgrep -f 'openclaw gateway'"
log_done "Config updated. Gateway should restart automatically."
