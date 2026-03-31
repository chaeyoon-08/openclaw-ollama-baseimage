#!/bin/bash
# entrypoint.sh — openclaw-ollama 컨테이너 자동 설정 스크립트
#
# References:
#   Ollama serve:            https://docs.ollama.com/linux
#   OpenClaw config:         https://docs.openclaw.ai/gateway/configuration-reference
#   OpenClaw Telegram:       https://docs.openclaw.ai/channels/telegram
#   OpenClaw gateway CLI:    https://docs.openclaw.ai/cli/gateway
#
# 환경변수:
#   필수: TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USER_IDS, OLLAMA_MODEL
#   선택: GITHUB_USERNAME, GITHUB_EMAIL, GITHUB_TOKEN, GITHUB_REPO_URL, OPENCLAW_TOKEN
#
#   GitHub 관련 변수는 모두 선택. GITHUB_USERNAME + GITHUB_EMAIL 이 없으면 GitHub 설정 전체 스킵.

set -e

# ── 로그 함수 ──────────────────────────────────────────────────────────────────
log_start()  { echo -e "\033[1;34m[ START ]\033[0m $1"; }
log_doing()  { echo -e "\033[0;36m[ DOING ]\033[0m $1"; }
log_ok()     { echo -e "\033[0;32m[  OK   ]\033[0m $1"; }
log_info()   { echo -e "\033[0;37m[ INFO  ]\033[0m $1"; }
log_warn()   { echo -e "\033[1;33m[ WARN  ]\033[0m $1"; }
log_error()  { echo -e "\033[0;31m[ ERROR ]\033[0m $1"; }
log_stop()   { echo -e "\033[1;31m[ STOP  ]\033[0m $1"; exit 1; }
log_done()   { echo -e "\033[1;32m[ DONE  ]\033[0m $1"; }

# ── 1. 필수 환경변수 검증 ────────────────────────────────────────────────────
log_start "Validating environment variables"

[ -z "$TELEGRAM_BOT_TOKEN" ]       && log_stop "TELEGRAM_BOT_TOKEN is required"
[ -z "$TELEGRAM_ALLOWED_USER_IDS" ] && log_stop "TELEGRAM_ALLOWED_USER_IDS is required (comma-separated numeric Telegram user IDs)"
[ -z "$OLLAMA_MODEL" ]              && log_stop "OLLAMA_MODEL is required (e.g. qwen3:14b)"

log_ok "Required variables present"
log_ok "  OLLAMA_MODEL             = ${OLLAMA_MODEL}"
log_ok "  TELEGRAM_ALLOWED_USER_IDS = ${TELEGRAM_ALLOWED_USER_IDS}"

# ── 2. GitHub 설정 (선택) ────────────────────────────────────────────────────
# GITHUB_USERNAME + GITHUB_EMAIL 이 모두 있을 때만 실행. 없으면 전체 스킵.
if [ -n "$GITHUB_USERNAME" ] && [ -n "$GITHUB_EMAIL" ]; then
    log_start "Configuring GitHub"

    # git 사용자 정보
    git config --global user.name  "$GITHUB_USERNAME"
    git config --global user.email "$GITHUB_EMAIL"
    log_ok "git user: ${GITHUB_USERNAME} <${GITHUB_EMAIL}>"

    # 인증 토큰 (선택)
    if [ -n "$GITHUB_TOKEN" ]; then
        git config --global credential.helper store
        echo "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com" \
            > /root/.git-credentials
        chmod 600 /root/.git-credentials
        log_ok "GitHub token stored"
    else
        log_info "GITHUB_TOKEN not set — git push will require manual auth"
    fi

    # 원격 repo 클론 (선택)
    # GITHUB_REPO_URL 이 있으면 /workspace 에 클론
    if [ -n "$GITHUB_REPO_URL" ]; then
        log_doing "Cloning repo: ${GITHUB_REPO_URL}"
        if [ -d "/workspace/.git" ]; then
            log_info "/workspace already has a git repo — skipping clone"
        else
            git clone "$GITHUB_REPO_URL" /workspace
            log_ok "Cloned into /workspace"
        fi
    else
        log_info "GITHUB_REPO_URL not set — skipping clone"
    fi
else
    log_info "GITHUB_USERNAME / GITHUB_EMAIL not set — skipping GitHub setup (optional)"
fi

# ── 2-1. openclaw workspace 자동 복원 ───────────────────────────────────────
# /workspace/.openclaw_copy 가 있으면 → /root/.openclaw/workspace 로 복원
# backup.sh로 백업 후 git push 해둔 내용을 컨테이너 재시작 시 git clone과 함께 복원됨
# /workspace/.openclaw_copy 가 없으면 → 빈 디렉터리 생성 (첫 시작 시)
if [ -d "/workspace/.openclaw_copy" ]; then
    log_doing "Restoring openclaw workspace from .openclaw_copy"
    mkdir -p /root/.openclaw/workspace
    cp -r /workspace/.openclaw_copy/. /root/.openclaw/workspace/
    log_ok "Workspace restored from /workspace/.openclaw_copy"
else
    mkdir -p /workspace/.openclaw_copy
    log_info "Created empty /workspace/.openclaw_copy"
fi

# ── 3. Ollama 서비스 시작 ────────────────────────────────────────────────────
log_start "Starting Ollama service"
ollama serve &
OLLAMA_PID=$!

log_doing "Waiting for Ollama API..."
RETRY=0
until curl -sf http://localhost:11434/ > /dev/null 2>&1; do
    sleep 1
    RETRY=$((RETRY + 1))
    [ $RETRY -ge 60 ] && log_stop "Ollama did not start within 60 seconds"
done
log_ok "Ollama is ready"

# ── 4. Ollama 모델 다운로드 ──────────────────────────────────────────────────
# 주의: OLLAMA_MODEL에 반드시 태그를 포함할 것 (예: qwen3:14b)
#       태그 없이 지정하면 :latest 로 시도하며, :latest 가 없는 모델은 오류 발생
#
# CLI 방식 대신 REST API(stream: true) 사용 이유:
#   CLI는 non-TTY 환경에서 진행바 \r을 줄바꿈으로 출력 → 로그 수천 줄 발생
#   API 스트리밍은 JSON 한 줄씩 수신 → 10% 단위 필터링으로 간결한 진행 로그 출력
# Source: https://github.com/ollama/ollama/blob/main/docs/api.md#pull-a-model
log_doing "Pulling Ollama model: ${OLLAMA_MODEL}"
_LAST_BUCKET=-1
curl -sf -X POST http://localhost:11434/api/pull \
    -d "{\"name\":\"${OLLAMA_MODEL}\"}" \
| while IFS= read -r line; do
    STATUS=$(printf '%s' "$line" | jq -r '.status    // empty' 2>/dev/null)
    TOTAL=$( printf '%s' "$line" | jq -r '.total     // 0'     2>/dev/null)
    DONE=$(  printf '%s' "$line" | jq -r '.completed // 0'     2>/dev/null)
    if [ "${TOTAL:-0}" -gt 0 ] 2>/dev/null; then
        PCT=$(( DONE * 100 / TOTAL ))
        BUCKET=$(( PCT / 10 * 10 ))
        if [ "$BUCKET" -ne "$_LAST_BUCKET" ]; then
            _LAST_BUCKET=$BUCKET
            log_doing "  ${STATUS}: ${BUCKET}%"
        fi
    elif [ -n "$STATUS" ]; then
        case "$STATUS" in
            "pulling manifest"|"verifying sha256 digest"|"writing manifest"|"success")
                log_doing "  ${STATUS}";;
        esac
    fi
done
log_ok "Model ready: ${OLLAMA_MODEL}"

# ── 5. OpenClaw 토큰 생성 (항상 내부 자동 생성) ─────────────────────────────
OPENCLAW_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)

# ── 6. allowFrom JSON 배열 생성 (쉼표 구분 → JSON 배열) ────────────────────
# TELEGRAM_ALLOWED_USER_IDS="123456789,987654321" → ["123456789","987654321"]
# Source: https://docs.openclaw.ai/channels/telegram
#   allowFrom은 수치형 Telegram user ID 문자열만 허용 (@username 불가)
ALLOW_FROM_JSON=$(
    echo "$TELEGRAM_ALLOWED_USER_IDS" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | jq -R . \
    | jq -s .
)

# ── 7. openclaw.json 생성 ────────────────────────────────────────────────────
# Source: https://docs.openclaw.ai/gateway/configuration-reference
#         https://docs.openclaw.ai/providers/ollama
#         https://docs.openclaw.ai/channels/telegram
log_doing "Writing OpenClaw configuration"
mkdir -p /root/.openclaw

jq -n \
    --arg     token      "$OPENCLAW_TOKEN" \
    --arg     bot_token  "$TELEGRAM_BOT_TOKEN" \
    --arg     model      "$OLLAMA_MODEL" \
    --argjson allow_from "$ALLOW_FROM_JSON" \
    '{
        gateway: {
            mode: "local",
            port: 18789,
            bind: "lan",
            auth: { mode: "token", token: $token }
        },
        models: {
            mode: "merge",
            providers: {
                ollama: {
                    baseUrl: "http://localhost:11434",
                    apiKey:  "ollama",
                    api:     "ollama",
                    models: [{
                        id:    $model,
                        name:  ("Ollama (" + $model + ")"),
                        input: ["text"],
                        cost:  { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
                    }]
                }
            }
        },
        agents: {
            defaults: {
                workspace: "/root/.openclaw/workspace",
                model: { primary: ("ollama/" + $model) }
            }
        },
        channels: {
            telegram: {
                enabled:   true,
                botToken:  $bot_token,
                dmPolicy:  "allowlist",
                allowFrom: $allow_from
            }
        }
    }' > /root/.openclaw/openclaw.json

log_ok "openclaw.json written"

# ── 8. OpenClaw gateway 시작 ────────────────────────────────────────────────
# Source: https://docs.openclaw.ai/cli/gateway
log_start "Starting OpenClaw gateway"
openclaw gateway &
OPENCLAW_PID=$!

# gateway 준비 대기
sleep 3

# ── 9. 유틸리티 스크립트 생성 ────────────────────────────────────────────────
# backup.sh  : openclaw workspace → /workspace/.openclaw_copy 백업
# restore.sh : /workspace/.openclaw_copy → openclaw workspace 복원
mkdir -p /workspace

if [ ! -f /workspace/backup.sh ]; then
cat > /workspace/backup.sh << 'SCRIPT'
#!/bin/bash
# backup.sh — openclaw workspace를 /workspace/.openclaw_copy 로 백업
# 컨테이너가 내려가기 전에 실행 후 git push로 작업 내용 보존

log_ok()    { echo -e "\033[0;32m[  OK   ]\033[0m $1"; }
log_doing() { echo -e "\033[0;36m[ DOING ]\033[0m $1"; }
log_done()  { echo -e "\033[1;32m[ DONE  ]\033[0m $1"; }

SRC="/root/.openclaw/workspace"
DST="/workspace/.openclaw_copy"

log_doing "Copying openclaw workspace -> .openclaw_copy"
mkdir -p "$DST"
cp -r "${SRC}/." "$DST/"
log_ok "Copied to ${DST}"
echo ""
log_done "백업 완료. 아래 명령어로 GitHub에 push하세요:"
echo ""
echo "  cd /workspace"
echo "  git add .openclaw_copy"
echo "  git commit -m 'backup: openclaw workspace'"
echo "  git push"
SCRIPT
chmod +x /workspace/backup.sh
log_ok "Created /workspace/backup.sh"
fi

if [ ! -f /workspace/restore.sh ]; then
cat > /workspace/restore.sh << 'SCRIPT'
#!/bin/bash
# restore.sh — /workspace/.openclaw_copy 를 openclaw workspace 로 복원
# 컨테이너 재시작 후 이전 작업 내용을 수동으로 불러올 때 사용
# (자동 복원: 컨테이너 시작 시 .openclaw_copy 가 있으면 entrypoint.sh 가 자동 처리)

log_ok()    { echo -e "\033[0;32m[  OK   ]\033[0m $1"; }
log_doing() { echo -e "\033[0;36m[ DOING ]\033[0m $1"; }
log_done()  { echo -e "\033[1;32m[ DONE  ]\033[0m $1"; }
log_stop()  { echo -e "\033[0;31m[ ERROR ]\033[0m $1"; exit 1; }

SRC="/workspace/.openclaw_copy"
DST="/root/.openclaw/workspace"

[ ! -d "$SRC" ] && log_stop "${SRC} 없음. backup.sh 실행 또는 git pull 먼저 진행하세요."

log_doing "Copying .openclaw_copy -> openclaw workspace"
mkdir -p "$DST"
cp -r "${SRC}/." "$DST/"
log_ok "Restored to ${DST}"
echo ""
log_done "복원 완료. 아래 명령어로 openclaw를 재시작하세요:"
echo ""
echo "  pkill -f openclaw-gateway"
echo ""
echo "  (잠시 후 자동으로 재시작됩니다)"
SCRIPT
chmod +x /workspace/restore.sh
log_ok "Created /workspace/restore.sh"
fi

log_done "All services started"
echo ""
echo "  Ollama model  : ${OLLAMA_MODEL}"
echo "  Gateway token : ${OPENCLAW_TOKEN}"
echo ""

# ── 컨테이너 유지 ────────────────────────────────────────────────────────────
# SIGTERM 수신 시 openclaw 종료 후 컨테이너 정상 종료
# openclaw 가 죽으면 (restore.sh 후 pkill 등) 자동 재시작
_stop() {
    log_warn "Shutting down..."
    kill "$OPENCLAW_PID" 2>/dev/null
    exit 0
}
trap _stop SIGTERM SIGINT

while true; do
    if ! kill -0 "$OPENCLAW_PID" 2>/dev/null; then
        log_warn "OpenClaw gateway stopped, restarting..."
        sleep 1
        openclaw gateway &
        OPENCLAW_PID=$!
    fi
    sleep 3
done
