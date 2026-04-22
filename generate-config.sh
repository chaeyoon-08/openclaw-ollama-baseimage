#!/bin/bash
# generate-config.sh -- .env 기반 openclaw.json 생성 (multi-agent)
#
# References:
#   OpenClaw config:       https://docs.openclaw.ai/gateway/configuration-reference
#   OpenClaw Telegram:     https://docs.openclaw.ai/channels/telegram
#   OpenClaw providers:    https://docs.openclaw.ai/providers/ollama
#   OpenClaw cron:         https://docs.openclaw.ai/automation/cron-jobs
#   OpenClaw subagents:    https://docs.openclaw.ai/tools/subagents
#
# Ollama 모델 등록:
#   generate-config.sh 실행 시점에 Ollama가 이미 기동 중 → /api/tags 쿼리로 모델 목록 확보
#   models.providers.ollama 블록에 명시 등록 (OLLAMA_API_KEY env var 단독 auto-discovery는
#   게이트웨이 라우팅 초기화 이후에 config overwrite가 발생하는 타이밍 문제로 신뢰 불가)
#   Source: https://docs.openclaw.ai/providers/ollama
#
# /models UI 버그 회피:
#   Issue #65500 (v2026.4.11 regression): models.providers.ollama.models에 등록된 모델이
#   /models UI에서 "model not allowed"로 차단됨. 회피책으로 agents.defaults.model.fallbacks에
#   이중 등록. primary가 ollama일 때만 발동.
#
# Heartbeat:
#   gcube 과금 환경 + 비동기 배치 워커 컨셉에 따라 항상 비활성화
#   30분마다 대형 모델(10GB+) 로드는 자원 낭비

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

# ── Provider 설정 ───────────────────────────────────────────────────────────
ORCH_PROVIDER=$(echo "$ORCHESTRATOR_MODEL" | cut -d'/' -f1)

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
    | tr -s ' \t' '\n' \
    | grep -v '^$' \
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
    read -ra _KEY_ENTRIES <<< "$MODEL_API_KEY"
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

# ── Worker model 설정 (subagents.model.primary) ──────────────────────────────
# WORKER_MODELS 첫 번째 항목 → agents.defaults.subagents.model.primary
#
# 현재 제약: sessions_spawn.model 파라미터 및 subagents.model.primary 설정은
#   OpenClaw 알려진 버그(Issue #65519 외 다수)로 무시되며, 모든 서브에이전트는
#   오케스트레이터의 primary 모델로 실행됨.
#   설정은 유지하여 버그 수정 시 자동 활성화되도록 보존.
_WORKER_MODEL_PRIMARY=""
if [ -n "$WORKER_MODELS" ]; then
    read -ra _WM_LIST <<< "$WORKER_MODELS"
    _WORKER_MODEL_PRIMARY="${_WM_LIST[0]}"
    log_ok "Worker model (subagent default): ${_WORKER_MODEL_PRIMARY}"
else
    log_info "WORKER_MODELS not set — subagents will inherit orchestrator model"
fi

# ── Ollama 모델 목록 조회 ────────────────────────────────────────────────────
# entrypoint.sh가 Ollama 기동 완료를 보장한 뒤 generate-config.sh를 호출함
# → curl 실패 시 빈 배열로 fallback (Ollama가 없는 순수 외부 provider 환경 대비)
_OLLAMA_MODELS_JSON="[]"
if _TAGS=$(curl -sf http://127.0.0.1:11434/api/tags 2>/dev/null); then
    _OLLAMA_MODELS_JSON=$(echo "$_TAGS" \
        | jq '[.models[].name | {id: ., name: .}]' 2>/dev/null || echo "[]")
    _OLLAMA_MODEL_COUNT=$(echo "$_OLLAMA_MODELS_JSON" | jq 'length')
    log_ok "Ollama models queried: ${_OLLAMA_MODEL_COUNT} found"
else
    log_warn "Ollama API unreachable — model list empty (external providers only)"
fi

# ── Fallbacks 이중 등록 (Issue #65500 회피) ──────────────────────────────────
# primary가 ollama일 때만 발동. Ollama 모델 중 primary 제외한 나머지를
# agents.defaults.model.fallbacks에 이중 등록하여 /models UI에 노출.
# provider prefix "ollama/"를 붙여 full model ID 형태로 변환.
_FALLBACKS_JSON="[]"
if [ "$ORCH_PROVIDER" = "ollama" ]; then
    _PRIMARY_MODEL_ID="${ORCHESTRATOR_MODEL#ollama/}"
    _FALLBACKS_JSON=$(echo "$_OLLAMA_MODELS_JSON" \
        | jq --arg primary "$_PRIMARY_MODEL_ID" \
             '[.[] | select(.id != $primary) | "ollama/" + .id]')
    _FALLBACK_COUNT=$(echo "$_FALLBACKS_JSON" | jq 'length')
    log_ok "Fallbacks registered for /models UI visibility: ${_FALLBACK_COUNT} models"
else
    log_info "Primary is non-ollama — fallbacks skipped"
fi

# ── openclaw.json 생성 ──────────────────────────────────────────────────────
log_doing "Generating openclaw.json"
mkdir -p /home/node/.openclaw

OPENCLAW_VERSION=$(openclaw --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
OPENCLAW_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# localModelLean 플래그: primary가 ollama일 때만 활성화 (v2026.4.15 신기능)
# browser/cron/message 등 heavyweight 기본 도구 드롭하여 prompt 크기 축소
_LOCAL_MODEL_LEAN="false"
if [ "$ORCH_PROVIDER" = "ollama" ]; then
    _LOCAL_MODEL_LEAN="true"
fi

jq -n \
    --arg     token              "$OPENCLAW_TOKEN" \
    --arg     bot_token          "$TELEGRAM_BOT_TOKEN" \
    --arg     orchestrator_model "$ORCHESTRATOR_MODEL" \
    --arg     worker_model       "$_WORKER_MODEL_PRIMARY" \
    --arg     oc_version         "$OPENCLAW_VERSION" \
    --arg     oc_now             "$OPENCLAW_NOW" \
    --argjson allow_from         "$ALLOW_FROM_JSON" \
    --argjson ollama_models      "$_OLLAMA_MODELS_JSON" \
    --argjson fallbacks          "$_FALLBACKS_JSON" \
    --argjson local_model_lean   "$_LOCAL_MODEL_LEAN" \
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
                    api: "ollama",
                    apiKey: "ollama-local",
                    baseUrl: "http://127.0.0.1:11434",
                    models: $ollama_models
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
                bootstrapMaxChars: 40000,
                experimental: { localModelLean: $local_model_lean },
                model: (
                    { primary: $orchestrator_model } +
                    (if ($fallbacks | length) > 0 then
                        { fallbacks: $fallbacks }
                    else {} end)
                ),
                subagents: (
                    {
                        maxSpawnDepth: 1,
                        maxConcurrent: 2,
                        runTimeoutSeconds: 300
                    } + (
                        if $worker_model != "" then
                            { model: { primary: $worker_model } }
                        else {} end
                    )
                ),
                heartbeat: { every: "0m" },
                thinkingDefault: "off"
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