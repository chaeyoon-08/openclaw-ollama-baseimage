#!/bin/bash
# generate-config.sh -- .env 기반 openclaw.json 생성 (multi-agent)
#
# References:
#   OpenClaw config:       https://docs.openclaw.ai/gateway/configuration-reference
#   OpenClaw Telegram:     https://docs.openclaw.ai/channels/telegram
#   OpenClaw providers:    https://docs.openclaw.ai/providers/ollama
#   OpenClaw heartbeat:    https://docs.openclaw.ai/gateway/heartbeat
#   OpenClaw cron:         https://docs.openclaw.ai/automation/cron-jobs
#   OpenClaw subagents:    https://docs.openclaw.ai/tools/subagents
#
# 요금 방어 로직:
#   [1] ORCHESTRATOR가 유료 provider이면 heartbeat 강제 비활성화 (every: "0m")
#       → heartbeat.model override는 반복 regression bug로 신뢰 불가 (#56788, #58137)
#   [2] subagents.model = $WORKER_MODEL (Ollama 고정)
#       → cron 잡 등 격리 세션 작업이 자동으로 로컬 모델 사용

set -e

# ── 로그 함수 ──────────────────────────────────────────────────────────────────
log_doing()  { echo -e "\033[0;36m[ DOING ]\033[0m $1"; }
log_ok()     { echo -e "\033[0;32m[  OK   ]\033[0m $1"; }
log_info()   { echo -e "\033[0;37m[ INFO  ]\033[0m $1"; }
log_warn()   { echo -e "\033[1;33m[ WARN  ]\033[0m $1"; }
log_stop()   { echo -e "\033[1;31m[ STOP  ]\033[0m $1"; exit 1; }

# ── .env 파일이 있으면 source ─────────────────────────────────────────────────
ENV_FILE="/home/node/.openclaw/.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
    log_ok "Loaded .env from ${ENV_FILE}"
fi

# ── 필수 환경변수 검증 ──────────────────────────────────────────────────────
[ -z "$TELEGRAM_BOT_TOKEN" ]        && log_stop "TELEGRAM_BOT_TOKEN is required"
[ -z "$TELEGRAM_ALLOWED_USER_IDS" ] && log_stop "TELEGRAM_ALLOWED_USER_IDS is required"
[ -z "$ORCHESTRATOR_MODEL" ]        && log_stop "ORCHESTRATOR_MODEL is required"

# ── Provider 및 모델 설정 ────────────────────────────────────────────────────
ORCH_PROVIDER=$(echo "$ORCHESTRATOR_MODEL" | cut -d'/' -f1)
# WORKER_MODEL: 쉼표로 여러 개 지정 가능. subagents 기본값은 첫 번째 모델 사용
WORK_MODEL=$(echo "${WORKER_MODEL:-$ORCHESTRATOR_MODEL}" | cut -d',' -f1 | tr -d ' ')
NLM_HOME="${NOTEBOOKLM_MCP_CLI_PATH:-/mnt/notebooklm/OpenClaw_Auth}"

# ── Ollama 모델 목록 구성 ────────────────────────────────────────────────────
# models: [] 자동 스캔 대신 명시적 목록 → gateway Config overwrite 시에도 전체 모델 보존
# (백그라운드 다운로드 중인 모델도 미리 등록 → 다운로드 완료 즉시 사용 가능)
_OLLAMA_MODELS_JSON="[]"
if [ "$ORCH_PROVIDER" = "ollama" ]; then
    _OMN=$(echo "$ORCHESTRATOR_MODEL" | cut -d'/' -f2-)
    _OLLAMA_MODELS_JSON=$(echo "$_OLLAMA_MODELS_JSON" | jq --arg m "$_OMN" '. + [$m]')
fi
IFS=',' read -ra _ALL_WM_LIST <<< "${WORKER_MODEL:-}"
for _wm in "${_ALL_WM_LIST[@]}"; do
    _wm=$(echo "$_wm" | tr -d ' ')
    _wp=$(echo "$_wm" | cut -d'/' -f1)
    _wmn=$(echo "$_wm" | cut -d'/' -f2-)
    if [ "$_wp" = "ollama" ]; then
        _OLLAMA_MODELS_JSON=$(echo "$_OLLAMA_MODELS_JSON" | jq --arg m "$_wmn" '. + [$m]')
    fi
done
log_info "Ollama models registered: ${_OLLAMA_MODELS_JSON}"

# ── Gateway 토큰 ─────────────────────────────────────────────────────────────
if [ -n "$OPENCLAW_GATEWAY_TOKEN" ]; then
    OPENCLAW_TOKEN="$OPENCLAW_GATEWAY_TOKEN"
else
    EXISTING_TOKEN=$(jq -r '.gateway.auth.token // empty' /home/node/.openclaw/openclaw.json 2>/dev/null || true)
    if [ -n "$EXISTING_TOKEN" ]; then
        OPENCLAW_TOKEN="$EXISTING_TOKEN"
    else
        OPENCLAW_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
    fi
fi

# ── allowFrom JSON 배열 생성 ─────────────────────────────────────────────────
# Source: https://docs.openclaw.ai/channels/telegram
ALLOW_FROM_JSON=$(
    echo "$TELEGRAM_ALLOWED_USER_IDS" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | jq -R . \
    | jq -s .
)

# ── 외부 provider 수집 (MODEL_API_KEY=provider/key,... 형식) ─────────────────
_PROVIDERS_JSON='{}'

_try_register_provider() {
    local _id="$1" _key="$2" _api="$3" _url="$4"
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

if [ -n "$MODEL_API_KEY" ]; then
    IFS=',' read -ra _KEY_ENTRIES <<< "$MODEL_API_KEY"
    for _entry in "${_KEY_ENTRIES[@]}"; do
        _provider=$(echo "$_entry" | cut -d'/' -f1)
        _key=$(echo "$_entry" | cut -d'/' -f2-)
        case "$_provider" in
            anthropic) _try_register_provider "anthropic" "$_key" "anthropic-messages"   "https://api.anthropic.com" ;;
            openai)    _try_register_provider "openai"    "$_key" "openai-responses"     "https://api.openai.com" ;;
            google)    _try_register_provider "google"    "$_key" "google-generative-ai" "https://generativelanguage.googleapis.com" ;;
            mistral)   _try_register_provider "mistral"   "$_key" "openai-completions"   "https://api.mistral.ai" ;;
            deepseek)  _try_register_provider "deepseek"  "$_key" "openai-completions"   "https://api.deepseek.com" ;;
            groq)      _try_register_provider "groq"      "$_key" "openai-completions"   "https://api.groq.com/openai" ;;
            *) log_warn "Unknown provider in MODEL_API_KEY: ${_provider} — skipped" ;;
        esac
    done
fi

# ── Heartbeat 설정 결정 ──────────────────────────────────────────────────────
# heartbeat.model override는 반복적인 known bug로 신뢰 불가
# 관련 이슈: openclaw#56788 (v2026.3.28 regression), #58137 (live session switch 간섭)
# 유료 provider 사용 시 heartbeat 강제 비활성화 → 요금 폭탄 방지
if [ "$ORCH_PROVIDER" = "ollama" ]; then
    HEARTBEAT_EVERY="30m"
    HEARTBEAT_MODEL="$ORCHESTRATOR_MODEL"
    log_info "Heartbeat enabled (every: 30m, model: ${HEARTBEAT_MODEL})"
else
    HEARTBEAT_EVERY="0m"
    HEARTBEAT_MODEL=""
    log_warn "Heartbeat disabled: ORCHESTRATOR_MODEL is a paid provider — preventing cost overrun"
    log_warn "  (heartbeat.model override is unreliable: openclaw#56788, #58137)"
fi

# ── openclaw.json 생성 ──────────────────────────────────────────────────────
log_doing "Generating openclaw.json"
mkdir -p /home/node/.openclaw

OPENCLAW_VERSION=$(openclaw --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
OPENCLAW_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n \
    --arg     token              "$OPENCLAW_TOKEN" \
    --arg     bot_token          "$TELEGRAM_BOT_TOKEN" \
    --arg     orchestrator_model "$ORCHESTRATOR_MODEL" \
    --arg     worker_model       "$WORK_MODEL" \
    --arg     heartbeat_every    "$HEARTBEAT_EVERY" \
    --arg     heartbeat_model    "$HEARTBEAT_MODEL" \
    --arg     nlm_home           "$NLM_HOME" \
    --arg     oc_version         "$OPENCLAW_VERSION" \
    --arg     oc_now             "$OPENCLAW_NOW" \
    --argjson allow_from         "$ALLOW_FROM_JSON" \
    --argjson ollama_models      "$_OLLAMA_MODELS_JSON" \
    '{
        meta: {
            lastTouchedVersion: $oc_version,
            lastTouchedAt: $oc_now
        },
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
                    models:  $ollama_models
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
                workspace: "/home/node/.openclaw/workspace",
                model: { primary: $orchestrator_model },
                subagents: {
                    model: $worker_model,
                    maxSpawnDepth: 1,
                    maxConcurrent: 4,
                    runTimeoutSeconds: 300
                },
                heartbeat: (
                    if $heartbeat_every == "0m" then
                        { every: "0m" }
                    else
                        { every: $heartbeat_every, model: $heartbeat_model, lightContext: true }
                    end
                )
            }
        },
        channels: {
            telegram: {
                enabled:   true,
                botToken:  $bot_token,
                dmPolicy:  "allowlist",
                allowFrom: $allow_from
            }
        },
        mcp: {
            servers: {
                notebooklm: {
                    command: "notebooklm-mcp",
                    args: [],
                    env: { NOTEBOOKLM_MCP_CLI_PATH: $nlm_home }
                },
                filesystem: {
                    command: "npx",
                    args: ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
                }
            }
        }
    }' > /home/node/.openclaw/openclaw.json

# ── 외부 provider merge ──────────────────────────────────────────────────────
if [ "$_PROVIDERS_JSON" != '{}' ]; then
    jq --argjson p "$_PROVIDERS_JSON" '.models.providers += $p' \
        /home/node/.openclaw/openclaw.json > /tmp/oc_merged.json \
        && mv /tmp/oc_merged.json /home/node/.openclaw/openclaw.json
    log_ok "External providers added"
fi

# ── 토큰 환경변수 export ─────────────────────────────────────────────────────
export OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_TOKEN"

log_ok "Config generation complete (token: ${OPENCLAW_TOKEN:0:8}...)"
