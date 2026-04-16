#!/bin/bash
# reload.sh -- .env 변경 후 openclaw.json 재생성 + gateway in-process reload
#
# 사용법: bash /usr/local/bin/reload.sh
#
# 동작:
#   1. /home/node/.openclaw/.env 를 읽어서 openclaw.json 재생성
#   2. 실행 중인 gateway에 SIGUSR1 전송 → in-process reload
#      (OPENCLAW_NO_RESPAWN=1 설정으로 새 프로세스 spawn 없이 동일 PID에서 재시작)
#      pkill 방식은 cold restart → Config overwrite를 유발하므로 사용하지 않음
#
# References:
#   OpenClaw config:   https://docs.openclaw.ai/gateway/configuration-reference
#   OPENCLAW_NO_RESPAWN: https://github.com/openclaw/openclaw/issues/65668

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

# -- gateway SIGUSR1 in-process reload --
# OPENCLAW_NO_RESPAWN=1: SIGUSR1 수신 시 새 프로세스 spawn 없이 동일 PID에서 재시작
# pkill은 cold restart를 유발하여 Config overwrite가 발생하므로 사용하지 않음
OPENCLAW_PID=$(pgrep -u node -f "openclaw gateway" 2>/dev/null | head -1 || true)

if [ -z "$OPENCLAW_PID" ]; then
    log_error "No running gateway found (pgrep -u node -f 'openclaw gateway' returned empty)."
    log_error "Is entrypoint.sh running? Check: docker logs <container>"
    exit 1
fi

log_warn "Sending SIGUSR1 to gateway (PID: ${OPENCLAW_PID}) — in-process reload..."
kill -USR1 "$OPENCLAW_PID"

sleep 2

if kill -0 "$OPENCLAW_PID" 2>/dev/null; then
    log_ok "Gateway reload complete (PID: ${OPENCLAW_PID} still alive)"
    log_done "Reload complete. New configuration is active."
else
    log_warn "Gateway PID ${OPENCLAW_PID} exited after SIGUSR1."
    log_warn "entrypoint.sh should auto-restart it. Check: pgrep -f 'openclaw gateway'"
fi
