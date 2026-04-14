#!/bin/bash
# nlm-reauth-finish.sh — NotebookLM 재인증 완료: nlm login 대기 + noVNC 정리
#
# 사용 방법:
#   bash /usr/local/bin/nlm-reauth-finish.sh
#
# nlm-reauth-start.sh 실행 후 사용자가 Google 로그인을 완료했을 때 호출.
# nlm login 프로세스 종료를 확인하고 Xvfb/noVNC 를 정리한다.

log_doing() { echo -e "\033[0;36m[ DOING ]\033[0m $1"; }
log_ok()    { echo -e "\033[0;32m[  OK   ]\033[0m $1"; }
log_warn()  { echo -e "\033[1;33m[ WARN  ]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ ERROR ]\033[0m $1"; }

# ── nlm login 완료 대기 (최대 30초) ──────────────────────────────────────────
if [ -f /tmp/nlm-loginproc.pid ]; then
    NLM_PID=$(cat /tmp/nlm-loginproc.pid)
    if kill -0 "$NLM_PID" 2>/dev/null; then
        log_doing "Waiting for nlm login to complete (max 30s)..."
        _WAIT=0
        while kill -0 "$NLM_PID" 2>/dev/null && [ "$_WAIT" -lt 30 ]; do
            sleep 1
            _WAIT=$((_WAIT + 1))
        done
        if kill -0 "$NLM_PID" 2>/dev/null; then
            log_warn "nlm login still running after 30s. Force stopping."
            kill "$NLM_PID" 2>/dev/null || true
        else
            log_ok "nlm login completed"
        fi
    else
        log_ok "nlm login already completed"
    fi
else
    log_warn "nlm-loginproc.pid not found — nlm-reauth-start.sh was not run first?"
fi

# ── 인증 파일 확인 ────────────────────────────────────────────────────────────
NLM_AUTH="${NOTEBOOKLM_MCP_CLI_PATH:-/mnt/notebooklm/OpenClaw_Auth}/profiles/default"
if [ -f "${NLM_AUTH}/cookies.json" ]; then
    _MTIME=$(stat -c "%y" "${NLM_AUTH}/cookies.json" 2>/dev/null | cut -d' ' -f1)
    log_ok "Auth file saved: ${NLM_AUTH}/cookies.json (updated: ${_MTIME})"
else
    log_error "Auth file not found: ${NLM_AUTH}/cookies.json"
    log_warn "nlm login log:"
    cat /tmp/nlm-login.log 2>/dev/null || true
    echo ""
    log_warn "Cleanup will proceed. Rerun nlm-reauth-start.sh to retry."
fi

# ── Xvfb / x11vnc / noVNC 정리 ────────────────────────────────────────────────
log_doing "Cleaning up Xvfb/noVNC..."

for _pidfile in /tmp/nlm-websockify.pid /tmp/nlm-x11vnc.pid \
                /tmp/nlm-xvfb.pid /tmp/nlm-loginproc.pid; do
    if [ -f "$_pidfile" ]; then
        _pid=$(cat "$_pidfile")
        kill "$_pid" 2>/dev/null || true
        rm -f "$_pidfile"
    fi
done

# pkill 보조 (pid 파일 없이 남은 프로세스)
pkill -f "Xvfb :99"             2>/dev/null || true
pkill -f "x11vnc.*rfbport 5900" 2>/dev/null || true
pkill -f "websockify.*6080"     2>/dev/null || true
rm -f /tmp/websockify.log /tmp/x11vnc.log /tmp/nlm-login.log

log_ok "Cleanup complete"
