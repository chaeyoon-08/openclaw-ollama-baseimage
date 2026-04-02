#!/bin/bash
# generate-config.sh -- .env 기반 openclaw.json 생성
#
# 동작:
#   1. 기본 설정 생성 (Ollama 자동 감지 + Telegram + 웹검색)
#   2. 외부 provider API 키가 있으면 providers에 추가
#   3. AGENT_* 환경변수가 있으면 멀티 에이전트 + A2A 자동 구성
#
# 환경변수:
#   필수: TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USER_IDS, OLLAMA_MODEL
#   선택: ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, MISTRAL_API_KEY,
#         DEEPSEEK_API_KEY, GROQ_API_KEY
#   선택: AGENT_N=역할명,provider/모델명 (N=1,2,3,...)
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
log_warn()   { echo -e "\033[1;33m[ WARN  ]\033[0m $1"; }
log_error()  { echo -e "\033[0;31m[ ERROR ]\033[0m $1"; }
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

# ── 역할 설명 매핑 함수 ──
_get_role_desc() {
    case "$1" in
        reasoning)  echo "추론, 분석, 복잡한 문제 해결 담당" ;;
        coding)     echo "코드 작성, 리뷰, 디버깅 담당" ;;
        writing)    echo "문서, 이메일, 번역 작성 담당" ;;
        search)     echo "정보 검색, 요약 담당" ;;
        general)    echo "일반 대화, 기타 작업 담당" ;;
        *)          echo "$1 역할 담당" ;;
    esac
}

# ── provider → API 키 환경변수 매핑 함수 ──
_get_provider_key() {
    case "$1" in
        anthropic) echo "$ANTHROPIC_API_KEY" ;;
        openai)    echo "$OPENAI_API_KEY" ;;
        google)    echo "$GEMINI_API_KEY" ;;
        mistral)   echo "$MISTRAL_API_KEY" ;;
        deepseek)  echo "$DEEPSEEK_API_KEY" ;;
        groq)      echo "$GROQ_API_KEY" ;;
        ollama)    echo "ollama" ;;
        *)         echo "" ;;
    esac
}

# ── provider → API 타입 매핑 함수 ──
_get_provider_api() {
    case "$1" in
        anthropic) echo "anthropic-messages" ;;
        openai)    echo "openai-responses" ;;
        google)    echo "google-generative-ai" ;;
        mistral)   echo "openai-completions" ;;
        deepseek)  echo "openai-completions" ;;
        groq)      echo "openai-completions" ;;
        *)         echo "" ;;
    esac
}

# ── provider → base URL 매핑 함수 ──
_get_provider_url() {
    case "$1" in
        anthropic) echo "https://api.anthropic.com" ;;
        openai)    echo "https://api.openai.com" ;;
        google)    echo "https://generativelanguage.googleapis.com" ;;
        mistral)   echo "https://api.mistral.ai" ;;
        deepseek)  echo "https://api.deepseek.com" ;;
        groq)      echo "https://api.groq.com/openai" ;;
        *)         echo "" ;;
    esac
}

# ── 1. 외부 provider 수집 ──
# API 키가 있는 provider만 등록
_PROVIDERS_JSON='{}'
_PROVIDERS_REGISTERED=""

_try_register_provider() {
    local _id="$1"
    local _key=$(_get_provider_key "$_id")
    local _api=$(_get_provider_api "$_id")
    local _url=$(_get_provider_url "$_id")

    if [ -n "$_key" ] && [ "$_key" != "ollama" ] && [ -n "$_api" ]; then
        # 이미 등록된 provider는 스킵
        echo "$_PROVIDERS_REGISTERED" | grep -q "$_id" && return
        _PROVIDERS_JSON=$(printf '%s' "$_PROVIDERS_JSON" | jq \
            --arg id  "$_id" \
            --arg api "$_api" \
            --arg key "$_key" \
            --arg url "$_url" \
            '. + {($id): {api: $api, apiKey: $key, baseUrl: $url, models: []}}')
        _PROVIDERS_REGISTERED="${_PROVIDERS_REGISTERED} ${_id}"
        log_ok "Provider registered: $_id"
    fi
}

# 기본 6개 provider 스캔
for _p in anthropic openai google mistral deepseek groq; do
    _try_register_provider "$_p"
done

# ── 2. AGENT_* 패턴 스캔 ──
_AGENT_LIST='[]'
_AGENT_IDS='["main"]'
_HAS_AGENTS=false

# AGENT_* 환경변수를 번호순으로 정렬하여 처리
env | grep '^AGENT_[0-9]*=' | sort -t= -k1 -V | while IFS= read -r _line; do
    _val=$(echo "$_line" | cut -d= -f2-)
    _role=$(echo "$_val" | cut -d, -f1)
    _provider_model=$(echo "$_val" | cut -d, -f2)
    _provider=$(echo "$_provider_model" | cut -d/ -f1)
    _model=$(echo "$_provider_model" | cut -d/ -f2-)

    # 검증
    if [ -z "$_role" ] || [ -z "$_provider" ] || [ -z "$_model" ]; then
        log_warn "Invalid AGENT entry: $_line (format: AGENT_N=role,provider/model)"
        continue
    fi

    # API provider인 경우 키 확인
    if [ "$_provider" != "ollama" ]; then
        _key=$(_get_provider_key "$_provider")
        if [ -z "$_key" ]; then
            _key_var=$(echo "${_provider}" | tr '[:lower:]' '[:upper:]')
            log_error "AGENT '$_role' requires ${_key_var}_API_KEY but it is not set. Skipping."
            continue
        fi
        _try_register_provider "$_provider"
    fi

    _desc=$(_get_role_desc "$_role")
    log_ok "Agent registered: $_role ($_provider/$_model) -- $_desc"

    # 임시 파일에 에이전트 정보 저장 (while 서브쉘 문제 우회)
    echo "${_role},${_provider}/${_model},${_desc}" >> /tmp/_agents_list.tmp
done

# 서브쉘에서 수집한 에이전트 정보 로드
_AGENT_LIST='[]'
_AGENT_IDS='["main"]'
_HAS_AGENTS=false

if [ -f /tmp/_agents_list.tmp ]; then
    while IFS= read -r _entry; do
        _role=$(echo "$_entry" | cut -d, -f1)
        _pm=$(echo "$_entry" | cut -d, -f2)
        _desc=$(echo "$_entry" | cut -d, -f3-)

        _AGENT_LIST=$(printf '%s' "$_AGENT_LIST" | jq \
            --arg id "$_role" \
            --arg model "$_pm" \
            --arg desc "$_desc" \
            '. + [{
                id: $id,
                model: $model,
                workspace: ("/root/.openclaw/workspace-" + $id),
                agentDir: ("/root/.openclaw/agents/" + $id)
            }]')
        _AGENT_IDS=$(printf '%s' "$_AGENT_IDS" | jq --arg id "$_role" '. + [$id]')
        _HAS_AGENTS=true
    done < /tmp/_agents_list.tmp
    rm -f /tmp/_agents_list.tmp
fi

# API 키만 있고 AGENT_*가 없는 경우에도 provider별 에이전트 자동 생성
if [ "$_HAS_AGENTS" = "false" ] && [ "$_PROVIDERS_JSON" != '{}' ]; then
    for _p in $(echo "$_PROVIDERS_REGISTERED"); do
        _AGENT_LIST=$(printf '%s' "$_AGENT_LIST" | jq \
            --arg id "$_p" \
            '. + [{
                id: $id,
                workspace: ("/root/.openclaw/workspace-" + $id),
                agentDir: ("/root/.openclaw/agents/" + $id)
            }]')
        _AGENT_IDS=$(printf '%s' "$_AGENT_IDS" | jq --arg id "$_p" '. + [$id]')
        _HAS_AGENTS=true
        log_ok "Auto-created agent for provider: $_p"
    done
fi

# ── 3. openclaw.json 생성 ──
log_doing "Generating openclaw.json"
mkdir -p /root/.openclaw

# 에이전트가 있으면 (AGENT_* 또는 API 키 기반)
if [ "$_HAS_AGENTS" = "true" ]; then
    # main 에이전트를 목록 앞에 추가
    _FULL_AGENT_LIST=$(printf '%s' "$_AGENT_LIST" | jq \
        --arg model "$OLLAMA_MODEL" \
        '[{
            id: "main",
            model: ("ollama/" + $model),
            workspace: "/root/.openclaw/workspace",
            agentDir: "/root/.openclaw/agents/main",
            default: true
        }] + .')

    jq -n \
        --arg       token      "$OPENCLAW_TOKEN" \
        --arg       bot_token  "$TELEGRAM_BOT_TOKEN" \
        --arg       model      "$OLLAMA_MODEL" \
        --argjson   allow_from "$ALLOW_FROM_JSON" \
        --argjson   agent_list "$_FULL_AGENT_LIST" \
        --argjson   a2a_allow  "$_AGENT_IDS" \
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
                        api:     "ollama"
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

    log_ok "Multi-agent config written"
    log_ok "  Agents: main + $(printf '%s' "$_AGENT_IDS" | jq -r '[.[] | select(. != "main")] | join(", ")')"
    log_ok "  A2A enabled"

    # 에이전트별 workspace/agentDir 생성
    printf '%s' "$_FULL_AGENT_LIST" | jq -r '.[].workspace' | while read -r _ws; do
        mkdir -p "$_ws"
    done
    printf '%s' "$_FULL_AGENT_LIST" | jq -r '.[].agentDir' | while read -r _ad; do
        mkdir -p "$_ad"
    done

else
    # 단일 에이전트 모드
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
                        api:     "ollama"
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

# ── 4. 외부 provider를 openclaw.json에 merge ──
if [ "$_PROVIDERS_JSON" != '{}' ]; then
    jq --argjson p "$_PROVIDERS_JSON" '.models.providers += $p' \
        /root/.openclaw/openclaw.json > /tmp/oc_merged.json \
        && mv /tmp/oc_merged.json /root/.openclaw/openclaw.json
    log_ok "External providers added"
fi

# -- 토큰 환경변수 export --
export OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_TOKEN"

log_ok "Config generation complete (token: ${OPENCLAW_TOKEN:0:8}...)"
