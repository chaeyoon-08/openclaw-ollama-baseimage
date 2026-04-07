#!/bin/bash
# generate-config.sh -- .env 기반 openclaw.json 생성
#
# 동작:
#   1. 기본 설정 생성 (Ollama 자동 감지 + Telegram + 웹검색)
#   2. 외부 provider API 키가 있으면 providers에 추가
#
# 환경변수:
#   필수: TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USER_IDS, OLLAMA_MODEL
#   선택: ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, MISTRAL_API_KEY,
#         DEEPSEEK_API_KEY, GROQ_API_KEY
#
# References:
#   OpenClaw config:       https://docs.openclaw.ai/gateway/configuration-reference
#   OpenClaw Telegram:     https://docs.openclaw.ai/channels/telegram
#   OpenClaw providers:    https://docs.openclaw.ai/providers/ollama

set -e

# -- 로그 함수 --
log_doing()  { echo -e "\033[0;36m[ DOING ]\033[0m $1"; }
log_ok()     { echo -e "\033[0;32m[  OK   ]\033[0m $1"; }
log_warn()   { echo -e "\033[1;33m[ WARN  ]\033[0m $1"; }
log_stop()   { echo -e "\033[1;31m[ STOP  ]\033[0m $1"; exit 1; }

# -- .env 파일이 있으면 source --
ENV_FILE="/root/.openclaw/.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
    log_ok "Loaded .env from ${ENV_FILE}"
fi

# -- 필수 환경변수 검증 --
[ -z "$TELEGRAM_BOT_TOKEN" ]        && log_stop "TELEGRAM_BOT_TOKEN is required"
[ -z "$TELEGRAM_ALLOWED_USER_IDS" ] && log_stop "TELEGRAM_ALLOWED_USER_IDS is required"
[ -z "$OLLAMA_MODEL" ]              && log_stop "OLLAMA_MODEL is required (e.g. qwen3.5:35b)"

# -- Gateway 토큰 --
if [ -n "$OPENCLAW_GATEWAY_TOKEN" ]; then
    OPENCLAW_TOKEN="$OPENCLAW_GATEWAY_TOKEN"
else
    EXISTING_TOKEN=$(jq -r '.gateway.auth.token // empty' /root/.openclaw/openclaw.json 2>/dev/null || true)
    if [ -n "$EXISTING_TOKEN" ]; then
        OPENCLAW_TOKEN="$EXISTING_TOKEN"
    else
        OPENCLAW_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
    fi
fi

# -- allowFrom JSON 배열 생성 --
# Source: https://docs.openclaw.ai/channels/telegram
ALLOW_FROM_JSON=$(
    echo "$TELEGRAM_ALLOWED_USER_IDS" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | jq -R . \
    | jq -s .
)

# -- 외부 provider 수집 --
_PROVIDERS_JSON='{}'

_try_register_provider() {
    local _id="$1"
    local _key="$2"
    local _api="$3"
    local _url="$4"

    if [ -n "$_key" ]; then
        _PROVIDERS_JSON=$(printf '%s' "$_PROVIDERS_JSON" | jq \
            --arg id  "$_id" \
            --arg api "$_api" \
            --arg key "$_key" \
            --arg url "$_url" \
            '. + {($id): {api: $api, apiKey: $key, baseUrl: $url, models: []}}')
        log_ok "Provider registered: $_id"
    fi
}

[ -n "$ANTHROPIC_API_KEY" ] && _try_register_provider "anthropic" "$ANTHROPIC_API_KEY" "anthropic-messages"   "https://api.anthropic.com"
[ -n "$OPENAI_API_KEY" ]    && _try_register_provider "openai"    "$OPENAI_API_KEY"    "openai-responses"      "https://api.openai.com"
[ -n "$GEMINI_API_KEY" ]    && _try_register_provider "google"    "$GEMINI_API_KEY"    "google-generative-ai"  "https://generativelanguage.googleapis.com"
[ -n "$MISTRAL_API_KEY" ]   && _try_register_provider "mistral"   "$MISTRAL_API_KEY"   "openai-completions"    "https://api.mistral.ai"
[ -n "$DEEPSEEK_API_KEY" ]  && _try_register_provider "deepseek"  "$DEEPSEEK_API_KEY"  "openai-completions"    "https://api.deepseek.com"
[ -n "$GROQ_API_KEY" ]      && _try_register_provider "groq"      "$GROQ_API_KEY"      "openai-completions"    "https://api.groq.com/openai"

# -- openclaw.json 생성 --
log_doing "Generating openclaw.json"
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
            auth: { mode: "token", token: $token },
            controlUi: { allowedOrigins: ["*"], dangerouslyDisableDeviceAuth: true }
        },
        models: {
            mode: "merge",
            providers: {
                ollama: {
                    baseUrl: "http://localhost:11434",
                    apiKey:  "ollama",
                    api:     "ollama",
                    models:  []
                }
            }
        },
        tools: {
            web: {
                search: {
                    enabled: true,
                    provider: "duckduckgo",
                    maxResults: 5,
                    timeoutSeconds: 30
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

# -- 외부 provider merge --
if [ "$_PROVIDERS_JSON" != '{}' ]; then
    jq --argjson p "$_PROVIDERS_JSON" '.models.providers += $p' \
        /root/.openclaw/openclaw.json > /tmp/oc_merged.json \
        && mv /tmp/oc_merged.json /root/.openclaw/openclaw.json
    log_ok "External providers added"
fi

# -- 토큰 환경변수 export --
export OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_TOKEN"

log_ok "Config generation complete (token: ${OPENCLAW_TOKEN:0:8}...)"
