#!/bin/bash
# nlm-reauth-start.sh — NotebookLM 재인증: 가상 디스플레이 + noVNC + nlm login 기동
#
# 사용 방법:
#   bash /usr/local/bin/nlm-reauth-start.sh
#
# 실행 후 사용자가 SSH 터널을 열고 localhost:6080/vnc.html 에서 Google 로그인.
# 완료 후 nlm-reauth-finish.sh 실행.
#
# References:
#   noVNC:      https://github.com/novnc/noVNC
#   Playwright: https://playwright.dev/python/docs/browsers
#   openbox:    https://openbox.org (VNC grey screen 방지용 경량 윈도우 매니저)

log_doing() { echo -e "\033[0;36m[ DOING ]\033[0m $1"; }
log_ok()    { echo -e "\033[0;32m[  OK   ]\033[0m $1"; }
log_warn()  { echo -e "\033[1;33m[ WARN  ]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ ERROR ]\033[0m $1"; }

# ── 기존 인스턴스 정리 ──────────────────────────────────────────────────────────
log_doing "Stopping any existing Xvfb/noVNC instances..."
pkill -f "Xvfb :99"             2>/dev/null || true
pkill -f "x11vnc.*rfbport 5900" 2>/dev/null || true
pkill -f "websockify.*6080"     2>/dev/null || true
pkill -f "openbox"              2>/dev/null || true
pkill -f "nlm login"            2>/dev/null || true
rm -f /tmp/nlm-xvfb.pid /tmp/nlm-x11vnc.pid \
       /tmp/nlm-websockify.pid /tmp/nlm-loginproc.pid
sleep 1

# ── Xvfb 가상 디스플레이 시작 (:99) ──────────────────────────────────────────
log_doing "Starting Xvfb virtual display :99..."
Xvfb :99 -screen 0 1280x800x24 &
echo $! > /tmp/nlm-xvfb.pid
sleep 1

if ! kill -0 "$(cat /tmp/nlm-xvfb.pid)" 2>/dev/null; then
    log_error "Xvfb failed to start"
    exit 1
fi
log_ok "Xvfb started (display :99)"

# ── openbox 윈도우 매니저 시작 ────────────────────────────────────────────────
# Ubuntu 22.04 + Docker 환경에서 x11vnc 연결 시 grey screen 방지
# Chrome 창이 Xvfb에 정상 렌더링되려면 윈도우 매니저가 필요함
log_doing "Starting openbox window manager..."
DISPLAY=:99 openbox > /tmp/openbox.log 2>&1 &
sleep 1
log_ok "openbox started"

# ── x11vnc VNC 서버 시작 (포트 5900) ──────────────────────────────────────────
# -bg 사용 안 함: Docker에서 포크 불안정 → & + echo $! 로 직접 PID 캡처
log_doing "Starting x11vnc (port 5900)..."
x11vnc -display :99 -forever -nopw -listen 127.0.0.1 -rfbport 5900 -quiet \
       > /tmp/x11vnc.log 2>&1 &
echo $! > /tmp/nlm-x11vnc.pid
sleep 1

if ! kill -0 "$(cat /tmp/nlm-x11vnc.pid)" 2>/dev/null; then
    log_error "x11vnc failed to start. Log: $(cat /tmp/x11vnc.log 2>/dev/null)"
    exit 1
fi
log_ok "x11vnc started (PID: $(cat /tmp/nlm-x11vnc.pid))"

# ── noVNC (websockify) 시작 (포트 6080) ───────────────────────────────────────
log_doing "Starting noVNC websockify (port 6080)..."
websockify --web /usr/share/novnc 6080 127.0.0.1:5900 \
           > /tmp/websockify.log 2>&1 &
echo $! > /tmp/nlm-websockify.pid
sleep 1

if ! kill -0 "$(cat /tmp/nlm-websockify.pid)" 2>/dev/null; then
    log_error "websockify failed to start. Log: $(cat /tmp/websockify.log 2>/dev/null)"
    exit 1
fi
log_ok "noVNC started (port 6080)"

# ── nlm login 백그라운드 시작 ─────────────────────────────────────────────────
# DISPLAY=:99: Playwright가 Xvfb 디스플레이에서 headful Chrome 기동
# PLAYWRIGHT_BROWSERS_PATH: 이미지 빌드 시 설치된 Chromium 경로 (ENV로 설정됨)
# < /dev/null: stdin 닫아 interactive prompt 블로킹 방지
# /usr/local/bin/nlm: PATH 의존 없이 명시적 경로
log_doing "Starting nlm login (headful mode on :99)..."
DISPLAY=:99 /usr/local/bin/nlm login < /dev/null > /tmp/nlm-login.log 2>&1 &
NLM_PID=$!
echo "$NLM_PID" > /tmp/nlm-loginproc.pid
sleep 2

if ! kill -0 "$NLM_PID" 2>/dev/null; then
    log_error "nlm login failed immediately. Log:"
    cat /tmp/nlm-login.log 2>/dev/null
    exit 1
fi
log_ok "nlm login running (PID: ${NLM_PID})"

# ── 접속 안내 출력 ────────────────────────────────────────────────────────────
echo ""
echo "  ┌──────────────────────────────────────────────────────┐"
echo "  │           NotebookLM 재인증 준비 완료                │"
echo "  ├──────────────────────────────────────────────────────┤"
echo "  │  SSH 터널 : ssh -L 6080:localhost:6080 <gcube-host>  │"
echo "  │  브라우저 : http://localhost:6080/vnc.html           │"
echo "  │                                                      │"
echo "  │  1. SSH 터널 열기                                    │"
echo "  │  2. 브라우저 접속                                    │"
echo "  │  3. Google 계정으로 로그인                           │"
echo "  │  4. 로그인 완료 후 에이전트에 '완료' 라고 입력       │"
echo "  └──────────────────────────────────────────────────────┘"
echo ""
