#!/bin/bash
# generate-config.sh -- .env 기반 openclaw.json 생성
#
# 용도: entrypoint.sh 최초 실행 및 reload.sh 재생성 시 공통 호출
# 입력: 환경변수 (직접 또는 .env에서 source)
# 출력: /root/.openclaw/openclaw.json
#
# 동작:
#   1. 기본 설정 생성 (Ollama + Telegram + 웹검색)
#   2. 외부 provider API 키가 있으면 providers에 추가
#   3. 외부 provider가 있으면 멀티 에이전트 + A2A 자동 구성
#
# References:
#   OpenClaw config:       https://docs.openclaw.ai/gateway/configuration-reference
#   OpenClaw Telegram:     https://docs.openclaw.ai/channels/telegram
#   OpenClaw providers:    https://docs.openclaw.ai/providers/ollama
#   OpenClaw multi-agent:  https://docs.openclaw.ai/concepts/multi-agent

set -e

# -- 로그 함수 --
log_doing()  { echo -e "\033[0;36m[ DOING ]\033[0m $1"; }
log_ok()     { echo -e "\033[0;32m[  OK   ]\033[0m $1"; }
log_info()   { echo -e "\033[0;37m[ INFO  ]\033[0m $1"; }
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
[ -z "$TELEGRAM_BOT_TOKEN" ]       && log_stop "TELEGRAM_BOT_TOKEN is required"
[ -z "$TELEGRAM_ALLOWED_USER_IDS" ] && log_stop "TELEGRAM_ALLOWED_USER_IDS is required"
[ -z "$OLLAMA_MODEL" ]              && log_stop "OLLAMA_MODEL is required (e.g. qwen3.5:35b)"

# -- Gateway 토큰 --
if [ -n "$OPENCLAW_GATEWAY_TOKEN" ]; then
    OPENCLAW_TOKEN="$OPENCLAW_GATEWAY_TOKEN"
else
    # 기존 openclaw.json에서 토큰 읽기 (재생성 시 토큰 유지)
    EXISTING_TOKEN=$(jq -r '.gateway.auth.token // empty' /root/.openclaw/openclaw.json 2>/dev/null || true)
    if [ -n "$EXISTING_TOKEN" ]; then
        OPENCLAW_TOKEN="$EXISTING_TOKEN"
    else
        OPENCLAW_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
    fi
fi

# -- allowFrom JSON 배열 생성 --
# Source: https://docs.openclaw.ai/channels/telegram
#   allowFrom은 수치형 Telegram user ID 문자열만 허용 (@username 불가)
ALLOW_FROM_JSON=$(
    echo "$TELEGRAM_ALLOWED_USER_IDS" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | jq -R . \
    | jq -s .
)

# -- 외부 provider 감지 --
# API 키가 있는 provider를 수집하여 멀티 에이전트 구성에 사용
_EXTRA_PROVIDERS='{}'
_AGENT_LIST='[]'
_AGENT_IDS='[]'
_HAS_EXTERNAL=false

_add_provider() {
    local _KEY="$1" _ID="$2" _API="$3" _URL="$4" _MODEL_PREFIX="$5"
    if [ -n "$_KEY" ]; then
        _EXTRA_PROVIDERS=$(printf '%s' "$_EXTRA_PROVIDERS" | jq \
            --arg id  "$_ID" \
            --arg api "$_API" \
            --arg key "$_KEY" \
            --arg url "$_URL" \
            '. + {($id): {api: $api, apiKey: $key, baseUrl: $url, models: []}}')

        # 에이전트 등록 정보 추가
        _AGENT_LIST=$(printf '%s' "$_AGENT_LIST" | jq \
            --arg id "$_ID" \
            --arg model_prefix "$_MODEL_PREFIX" \
            '. + [{
                id: $id,
                workspace: ("/root/.openclaw/workspace-" + $id),
                agentDir: ("/root/.openclaw/agents/" + $id)
            }]')
        _AGENT_IDS=$(printf '%s' "$_AGENT_IDS" | jq --arg id "$_ID" '. + [$id]')
        _HAS_EXTERNAL=true

        log_ok "Provider registered: $_ID"
    fi
}

# Source: https://docs.openclaw.ai/providers
_add_provider "$ANTHROPIC_API_KEY" "anthropic" "anthropic-messages"  "https://api.anthropic.com"     "anthropic/"
_add_provider "$OPENAI_API_KEY"    "openai"    "openai-responses"     "https://api.openai.com"        "openai/"
_add_provider "$GEMINI_API_KEY"    "google"    "google-generative-ai" "https://generativelanguage.googleapis.com" "google/"
_add_provider "$MISTRAL_API_KEY"   "mistral"   "openai-completions"   "https://api.mistral.ai"        "mistral/"
_add_provider "$DEEPSEEK_API_KEY"  "deepseek"  "openai-completions"   "https://api.deepseek.com"      "deepseek/"
_add_provider "$GROQ_API_KEY"      "groq"      "openai-completions"   "https://api.groq.com/openai"   "groq/"

# -- openclaw.json 생성 --
# Source: https://docs.openclaw.ai/gateway/configuration-reference
log_doing "Generating openclaw.json"
mkdir -p /root/.openclaw

if [ "$_HAS_EXTERNAL" = "true" ]; then
    # ── 멀티 에이전트 모드 ──
    # main(Ollama) + 외부 provider 에이전트들
    # Source: https://docs.openclaw.ai/concepts/multi-agent

    # main 에이전트를 agent list 앞에 추가
    _FULL_AGENT_LIST=$(printf '%s' "$_AGENT_LIST" | jq \
        --arg model "$OLLAMA_MODEL" \
        '[{
            id: "main",
            model: ("ollama/" + $model),
            workspace: "/root/.openclaw/workspace",
            agentDir: "/root/.openclaw/agents/main",
            default: true
        }] + .')

    # A2A allow 목록: main + 모든 외부 에이전트
    _A2A_ALLOW=$(printf '%s' "$_AGENT_IDS" | jq '. + ["main"]')

    jq -n \
        --arg       token      "$OPENCLAW_TOKEN" \
        --arg       bot_token  "$TELEGRAM_BOT_TOKEN" \
        --arg       model      "$OLLAMA_MODEL" \
        --argjson   allow_from "$ALLOW_FROM_JSON" \
        --argjson   agent_list "$_FULL_AGENT_LIST" \
        --argjson   a2a_allow  "$_A2A_ALLOW" \
        '{
            gateway: {
                mode: "local",
                port: 18789,
                bind: "lan",
                auth: { mode: "token", token: $token },
                controlUi: { allowedOrigins: ["*"], dangerouslyDisableDeviceAuth: true }
            },
            models: {
                mode: "replace",
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
            tools: {
                web: {
                    search: {
                        enabled: true,
                        provider: "duckduckgo",
                        maxResults: 5,
                        timeoutSeconds: 30
                    }
                },
                agentToAgent: {
                    enabled: true,
                    allow: $a2a_allow
                }
            },
            agents: {
                defaults: {
                    workspace: "/root/.openclaw/workspace",
                    model: { primary: ("ollama/" + $model) }
                },
                list: $agent_list
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

    log_ok "Multi-agent config written (agents: main + $(printf '%s' "$_AGENT_IDS" | jq -r 'join(", ")'))"
    log_ok "A2A enabled (allow: $(printf '%s' "$_A2A_ALLOW" | jq -r 'join(", ")'))"

    # 에이전트별 workspace/agentDir 디렉터리 생성
    printf '%s' "$_AGENT_LIST" | jq -r '.[].workspace' | while read -r _ws; do
        mkdir -p "$_ws"
    done
    printf '%s' "$_AGENT_LIST" | jq -r '.[].agentDir' | while read -r _ad; do
        mkdir -p "$_ad"
    done
    mkdir -p /root/.openclaw/agents/main
    log_ok "Agent directories created"

else
    # ── 단일 에이전트 모드 ──
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
                mode: "replace",
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

    log_ok "Single-agent config written"
fi

# -- 외부 provider를 openclaw.json에 추가 --
if [ "$_EXTRA_PROVIDERS" != '{}' ]; then
    jq --argjson p "$_EXTRA_PROVIDERS" '.models.providers += $p' \
        /root/.openclaw/openclaw.json > /tmp/oc_merged.json \
        && mv /tmp/oc_merged.json /root/.openclaw/openclaw.json
    log_ok "External providers added to openclaw.json"
else
    log_info "No external provider API keys set -- using Ollama only"
fi

# -- 토큰 환경변수 export (gateway 시작 시 필요) --
export OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_TOKEN"

log_ok "Config generation complete (token: ${OPENCLAW_TOKEN:0:8}...)"
