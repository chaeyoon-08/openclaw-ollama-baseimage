#!/bin/bash
# generate-config.sh -- .env 기반 openclaw.json 생성 (multi-agent)
#
# References:
#   OpenClaw config:       https://docs.openclaw.ai/gateway/configuration-reference
#   OpenClaw env vars:     https://docs.openclaw.ai/help/environment
#   OpenClaw Telegram:     https://docs.openclaw.ai/channels/telegram
#   OpenClaw providers:    https://docs.openclaw.ai/providers/ollama
#   OpenClaw cron:         https://docs.openclaw.ai/automation/cron-jobs
#   OpenClaw subagents:    https://docs.openclaw.ai/tools/subagents
#
# 보안 정책 — 시크릿 placeholder:
#   시크릿(gateway.auth.token, channels.telegram.botToken, models.providers.*.apiKey)은
#   실제 값 대신 ${VAR} 형태 placeholder를 박아 디스크 평문 저장을 우회.
#   OpenClaw gateway가 부팅 시 process env에서 메모리로 보간 (${VAR} string substitution).
#   entrypoint.sh가 시크릿 env(OPENCLAW_GATEWAY_TOKEN, TELEGRAM_BOT_TOKEN, *_API_KEY)를
#   사전에 process env로 export하므로 본 스크립트는 placeholder 박는 역할만 수행.
#   Source: https://docs.openclaw.ai/help/environment
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

# ── .env 파일이 있으면 source (비시크릿만 포함됨) ────────────────────────────
# 시크릿은 process env에 이미 존재하며, .env에 없으므로 덮어써지지 않음.
ENV_FILE="/home/node/.openclaw/.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
    log_ok "Loaded .env from ${ENV_FILE}"
fi

# ── 필수 환경변수 검증 ──────────────────────────────────────────────────────
[ -z "$TELEGRAM_BOT_TOKEN" ]        && log_stop "TELEGRAM_BOT_TOKEN is required (process env)"
[ -z "$TELEGRAM_ALLOWED_USER_IDS" ] && log_stop "TELEGRAM_ALLOWED_USER_IDS is required"
[ -z "$ORCHESTRATOR_MODEL" ]        && log_stop "ORCHESTRATOR_MODEL is required"
[ -z "$OPENCLAW_GATEWAY_TOKEN" ]    && log_stop "OPENCLAW_GATEWAY_TOKEN is required (entrypoint.sh should set this)"

# ── Provider 설정 ───────────────────────────────────────────────────────────
ORCH_PROVIDER=$(echo "$ORCHESTRATOR_MODEL" | cut -d'/' -f1)

# ── allowFrom JSON 배열 생성 ─────────────────────────────────────────────────
# Source: https://docs.openclaw.ai/channels/telegram
ALLOW_FROM_JSON=$(
    echo "$TELEGRAM_ALLOWED_USER_IDS" \
    | tr -s ' \t' '\n' \
    | grep -v '^$' \
    | jq -R . \
    | jq -s .
)

# ── 외부 provider 수집 (process env 기반) ──────────────────────────────────
# entrypoint.sh가 MODEL_API_KEY를 split해서 ANTHROPIC_API_KEY, OPENAI_API_KEY 등으로
# 이미 export 한 상태. 본 스크립트는 어떤 provider env가 존재하는지 확인하고
# 해당 provider 블록을 ${VAR_NAME} placeholder로 등록.
_PROVIDERS_JSON='{}'

# _try_register_provider — provider 블록 등록 (시크릿은 placeholder)
# 인자: $1=provider id, $2=env var 이름 (값 X), $3=api type, $4=base URL
_try_register_provider() {
    local _id="$1" _envvar="$2" _api="$3" _url="$4"
    # process env에 해당 변수가 실제로 존재하는지 확인 (indirect expansion: ${!_envvar})
    if [ -n "${!_envvar}" ]; then
        local _placeholder="\${${_envvar}}"
        _PROVIDERS_JSON=$(printf '%s' "$_PROVIDERS_JSON" | jq \
            --arg id          "$_id" \
            --arg api         "$_api" \
            --arg placeholder "$_placeholder" \
            --arg url         "$_url" \
            '. + {($id): {api: $api, apiKey: $placeholder, baseUrl: $url, models: []}}')
        log_ok "Provider registered: $_id (apiKey via \${${_envvar}})"
    fi
}

# 등록 가능한 provider 전수 점검 (process env에 키가 있는 것만 등록됨)
_try_register_provider "anthropic" "ANTHROPIC_API_KEY" "anthropic-messages"   "https://api.anthropic.com"
_try_register_provider "openai"    "OPENAI_API_KEY"    "openai-responses"     "https://api.openai.com"
_try_register_provider "google"    "GOOGLE_API_KEY"    "google-generative-ai" "https://generativelanguage.googleapis.com"
_try_register_provider "mistral"   "MISTRAL_API_KEY"   "openai-completions"   "https://api.mistral.ai"
_try_register_provider "deepseek"  "DEEPSEEK_API_KEY"  "openai-completions"   "https://api.deepseek.com"
_try_register_provider "groq"      "GROQ_API_KEY"      "openai-completions"   "https://api.groq.com/openai"

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
#
# contextWindow/maxTokens 주입:
#   OpenClaw는 기동 시 GGUF 메타데이터의 context_length를 읽어 num_ctx로 그대로 전달함.
#   이 값이 모델마다 100K~200K 수준이라 VRAM·속도에 악영향 → openclaw.json에 명시적으로
#   contextWindow/maxTokens를 박아 오버라이드함. Source: OpenClaw providers/ollama 문서.
#   qwen3 계열은 max 40K 제약이 있어 32K로 clamp (64K 요청 시 Ollama가 자동 clamp하지만
#   명시적으로 32K 박아 로그 혼동 방지). 그 외 모델은 DEFAULT_CONTEXT_WINDOW(env) 사용.
_OLLAMA_MODELS_JSON="[]"
if _TAGS=$(curl -sf http://127.0.0.1:11434/api/tags 2>/dev/null); then
    _OLLAMA_MODELS_JSON=$(echo "$_TAGS" \
        | jq --argjson default_ctx "${DEFAULT_CONTEXT_WINDOW:-65536}" \
             --argjson default_max "${DEFAULT_MAX_TOKENS:-8192}" \
             '[.models[].name | {
                 id: .,
                 name: .,
                 contextWindow: (if startswith("qwen3:") then 32768 else $default_ctx end),
                 maxTokens: $default_max
             }]' 2>/dev/null || echo "[]")
    _OLLAMA_MODEL_COUNT=$(echo "$_OLLAMA_MODELS_JSON" | jq 'length')
    log_ok "Ollama models queried: ${_OLLAMA_MODEL_COUNT} found (contextWindow injected)"
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
log_doing "Generating openclaw.json (secrets as \${VAR} placeholders)"
mkdir -p /home/node/.openclaw

OPENCLAW_VERSION=$(openclaw --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
OPENCLAW_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# localModelLean 플래그: primary가 ollama일 때만 활성화 (v2026.4.15 신기능)
# browser/cron/message 등 heavyweight 기본 도구 드롭하여 prompt 크기 축소
_LOCAL_MODEL_LEAN="false"
if [ "$ORCH_PROVIDER" = "ollama" ]; then
    _LOCAL_MODEL_LEAN="true"
fi

# 시크릿 placeholder는 single quote 안의 jq script에 직접 박아 bash expansion 방지.
# token / botToken 필드는 string literal로 ${VAR} 형태 보존 → openclaw.json에 그대로 기록.
jq -n \
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
            auth: { mode: "token", token: "${OPENCLAW_GATEWAY_TOKEN}" },
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
                botToken:  "${TELEGRAM_BOT_TOKEN}",
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
    log_ok "External providers added (apiKey as \${VAR} placeholders)"
fi

log_ok "Config generation complete (all secrets as placeholders)"