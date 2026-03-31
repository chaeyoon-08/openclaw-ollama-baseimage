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

log_done "All services started"
echo ""
echo "  Ollama model  : ${OLLAMA_MODEL}"
echo "  Gateway token : ${OPENCLAW_TOKEN}"
echo ""

# 컨테이너 유지 (gateway 종료 시 컨테이너도 종료)
wait $OPENCLAW_PID
