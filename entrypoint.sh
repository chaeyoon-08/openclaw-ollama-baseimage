#!/bin/bash
# entrypoint.sh — openclaw multi-agent 컨테이너 자동 설정 스크립트
#
# References:
#   Ollama serve:            https://docs.ollama.com/linux
#   OpenClaw config:         https://docs.openclaw.ai/gateway/configuration-reference
#   OpenClaw Telegram:       https://docs.openclaw.ai/channels/telegram
#   OpenClaw gateway CLI:    https://docs.openclaw.ai/cli/gateway
#   gosu (user switch):      https://github.com/tianon/gosu
#
# 환경변수 필수: TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USER_IDS, ORCHESTRATOR_MODEL
# 환경변수 선택: WORKER_MODEL, MODEL_API_KEY, NOTEBOOKLM_MCP_CLI_PATH, GITHUB_*

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

# 하위 호환: OLLAMA_MODEL → ORCHESTRATOR_MODEL 자동 변환
if [ -z "$ORCHESTRATOR_MODEL" ] && [ -n "$OLLAMA_MODEL" ]; then
    export ORCHESTRATOR_MODEL="ollama/${OLLAMA_MODEL}"
    log_warn "OLLAMA_MODEL is deprecated. Auto-converted: ORCHESTRATOR_MODEL=${ORCHESTRATOR_MODEL}"
fi

[ -z "$TELEGRAM_BOT_TOKEN" ]        && log_stop "TELEGRAM_BOT_TOKEN is required"
[ -z "$TELEGRAM_ALLOWED_USER_IDS" ] && log_stop "TELEGRAM_ALLOWED_USER_IDS is required"
[ -z "$ORCHESTRATOR_MODEL" ]        && log_stop "ORCHESTRATOR_MODEL is required (e.g. ollama/qwen3:14b or anthropic/claude-sonnet-4-6)"

# ── Provider 감지 ──────────────────────────────────────────────────────────
ORCH_PROVIDER=$(echo "$ORCHESTRATOR_MODEL" | cut -d'/' -f1)
WORK_MODEL="${WORKER_MODEL:-$ORCHESTRATOR_MODEL}"
WORK_PROVIDER=$(echo "$WORK_MODEL" | cut -d'/' -f1)

log_ok "Required variables present"
log_ok "  ORCHESTRATOR_MODEL        = ${ORCHESTRATOR_MODEL}"
log_ok "  WORKER_MODEL              = ${WORK_MODEL}"
log_ok "  TELEGRAM_ALLOWED_USER_IDS = ${TELEGRAM_ALLOWED_USER_IDS}"

# ── 요금 폭탄 방어: 유료 Orchestrator + 비-Ollama Worker 조합 차단 ──────────
# cron/heartbeat 백그라운드 작업이 WORKER_MODEL을 사용 → 유료 환경에서 Ollama 필수
if [ "$ORCH_PROVIDER" != "ollama" ]; then
    if [ "$WORK_PROVIDER" != "ollama" ]; then
        log_stop "ORCHESTRATOR_MODEL is a paid provider but WORKER_MODEL is not set to an Ollama model.
          Background/cron tasks would incur API costs.
          Set WORKER_MODEL=ollama/<model>:<tag> to continue."
    fi
    # 유료 provider API 키 등록 여부 확인
    echo "$MODEL_API_KEY" | tr ',' '\n' | grep -q "^${ORCH_PROVIDER}/" \
        || log_stop "ORCHESTRATOR_MODEL uses provider '${ORCH_PROVIDER}' but no matching MODEL_API_KEY entry found.
          Add MODEL_API_KEY=${ORCH_PROVIDER}/<your-api-key>"
fi

# Ollama 필요 여부 판단 (ORCHESTRATOR 또는 WORKER 중 하나라도 ollama이면 시작)
NEEDS_OLLAMA=false
[ "$ORCH_PROVIDER" = "ollama" ] && NEEDS_OLLAMA=true
[ "$WORK_PROVIDER" = "ollama" ] && NEEDS_OLLAMA=true

# ── 2. GitHub 설정 (선택) ────────────────────────────────────────────────────
# GITHUB_USERNAME + GITHUB_EMAIL 이 모두 있을 때만 실행
if [ -n "$GITHUB_USERNAME" ] && [ -n "$GITHUB_EMAIL" ]; then
    log_start "Configuring GitHub"

    git config --global user.name  "$GITHUB_USERNAME"
    git config --global user.email "$GITHUB_EMAIL"
    log_ok "git user: ${GITHUB_USERNAME} <${GITHUB_EMAIL}>"

    if [ -n "$GITHUB_TOKEN" ]; then
        git config --global credential.helper store
        echo "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com" \
            > /root/.git-credentials
        chmod 600 /root/.git-credentials
        log_ok "GitHub token stored"
    else
        log_info "GITHUB_TOKEN not set — git push will require manual auth"
    fi

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
    log_info "GITHUB_USERNAME / GITHUB_EMAIL not set — skipping GitHub setup"
fi

# ── 3. Ollama 서비스 시작 (필요 시만) ───────────────────────────────────────
if [ "$NEEDS_OLLAMA" = "true" ]; then
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

    # ── 4. Ollama 모델 다운로드 ──────────────────────────────────────────────
    # REST API pull: CLI는 non-TTY에서 \r→줄바꿈으로 로그 폭발. API 스트리밍으로 대체.
    # Source: https://github.com/ollama/ollama/blob/main/docs/api.md#pull-a-model
    _pull_model() {
        local _model="$1"
        log_doing "Pulling Ollama model: ${_model}"
        _LAST_BUCKET=-1
        curl -sf -X POST http://localhost:11434/api/pull \
            -d "{\"name\":\"${_model}\"}" \
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
        log_ok "Model ready: ${_model}"
    }

    # Orchestrator 모델 pull
    ORCH_MODEL_NAME=$(echo "$ORCHESTRATOR_MODEL" | cut -d'/' -f2-)
    _pull_model "$ORCH_MODEL_NAME"

    # Worker 모델 pull (Orchestrator와 다를 때만)
    if [ "$WORK_PROVIDER" = "ollama" ] && [ "$WORK_MODEL" != "$ORCHESTRATOR_MODEL" ]; then
        WORK_MODEL_NAME=$(echo "$WORK_MODEL" | cut -d'/' -f2-)
        _pull_model "$WORK_MODEL_NAME"
    fi
else
    log_info "Ollama not required — skipping Ollama start"
fi

# ── 5. node 사용자 디렉터리 권한 설정 ───────────────────────────────────────
# root 단계에서 먼저 수행 (gosu 이후에는 chown 불가)
log_start "Setting up node user environment"

chown -R node:node /home/node/.openclaw
chown -R node:node /home/node/.notebooklm 2>/dev/null || true

# NOTEBOOKLM_MCP_CLI_PATH 마운트 경로 처리
NLM_HOME="${NOTEBOOKLM_MCP_CLI_PATH:-/mnt/notebooklm/OpenClaw_Auth}"
export NOTEBOOKLM_MCP_CLI_PATH="$NLM_HOME"

if [ -d "$NLM_HOME" ]; then
    chown -R node:node "$NLM_HOME" 2>/dev/null || true
    log_ok "NOTEBOOKLM_MCP_CLI_PATH: ${NLM_HOME}"
else
    log_warn "NOTEBOOKLM_MCP_CLI_PATH path does not exist: ${NLM_HOME}"
    log_warn "  NotebookLM MCP will not function until the path is mounted."
fi

# ── 6. workspace 템플릿 복사 ────────────────────────────────────────────────
log_start "Copying workspace templates"
WORKSPACE="/home/node/.openclaw/workspace"
mkdir -p "$WORKSPACE"

# MEMORY.md를 sentinel로 최초 실행 여부 판단 — 존재하면 모든 복사 건너뜀 (사용자 데이터 보호)
if [ ! -f "$WORKSPACE/MEMORY.md" ]; then
    # 최초 실행 (또는 데이터 없는 빈 볼륨) — 전체 템플릿 복사
    log_ok "First run detected — initializing workspace from templates"
    cp /templates/AGENTS.md "$WORKSPACE/AGENTS.md"
    cp /templates/SOUL.md   "$WORKSPACE/SOUL.md"
    cp /templates/TOOLS.md  "$WORKSPACE/TOOLS.md"
    cp /templates/MEMORY.md "$WORKSPACE/MEMORY.md"
else
    # 재시작 또는 데이터 보존 환경 — 기존 파일 유지, 덮어쓰기 없음
    log_info "Workspace already initialized — skipping template copy (preserving user data)"
fi

chown -R node:node "$WORKSPACE"
log_ok "Workspace ready"

# ── 7. 환경변수 → .env 덤프 ──────────────────────────────────────────────────
# 사용자가 나중에 .env를 직접 수정 + reload.sh로 설정 갱신 가능
log_doing "Dumping environment variables to .env"
ENV_FILE="/home/node/.openclaw/.env"
cat > "$ENV_FILE" << ENVEOF
# openclaw .env -- 환경변수 설정 파일
# 수정 후 reload.sh 실행으로 반영: bash /usr/local/bin/reload.sh
#
# 필수
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_ALLOWED_USER_IDS=${TELEGRAM_ALLOWED_USER_IDS}
ORCHESTRATOR_MODEL=${ORCHESTRATOR_MODEL}

# 선택: Worker 모델 (미설정 시 ORCHESTRATOR_MODEL 상속)
# ORCHESTRATOR가 유료 모델이면 반드시 ollama/<model>:<tag> 형식으로 지정
WORKER_MODEL=${WORKER_MODEL:-}

# 선택: 외부 provider API 키 (provider/key 형식, 쉼표로 여러 개)
MODEL_API_KEY=${MODEL_API_KEY:-}

# 선택: Gateway 토큰 (미설정 시 자동 생성, 설정 시 재시작 후에도 유지)
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN:-}

# 선택: NotebookLM 인증 경로 (Dropbox 마운트 경로)
NOTEBOOKLM_MCP_CLI_PATH=${NLM_HOME}

# 선택: GitHub
GITHUB_USERNAME=${GITHUB_USERNAME:-}
GITHUB_EMAIL=${GITHUB_EMAIL:-}
GITHUB_TOKEN=${GITHUB_TOKEN:-}
GITHUB_REPO_URL=${GITHUB_REPO_URL:-}
ENVEOF
chmod 600 "$ENV_FILE"
chown node:node "$ENV_FILE"
log_ok ".env written: ${ENV_FILE}"

# ── 8. openclaw.json 생성 (generate-config.sh 호출) ─────────────────────────
# openclaw.json 항상 재생성: anomaly 상태 제거 → full scope fresh pairing 보장
# token은 generate-config.sh가 기존 파일에서 먼저 읽어 유지함
# nodes/ 클리어: 기존 operator.read pairing 레코드 제거 → fresh pairing 강제
CONFIG_FILE="/home/node/.openclaw/openclaw.json"
rm -rf /home/node/.openclaw/nodes 2>/dev/null || true
rm -f  /home/node/.openclaw/openclaw.json.bak 2>/dev/null || true
bash /usr/local/bin/generate-config.sh
chown node:node "$CONFIG_FILE"
OPENCLAW_TOKEN=$(jq -r '.gateway.auth.token' "$CONFIG_FILE")

# ── 9. OpenClaw gateway 시작 (node 사용자로 실행) ────────────────────────────
# Source: https://docs.openclaw.ai/cli/gateway
# gosu로 root → node 전환하여 보안 실행
log_start "Starting OpenClaw gateway"

export OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_TOKEN}"
gosu node openclaw gateway &
OPENCLAW_PID=$!

sleep 3

log_done "All services started"
echo ""
echo "  Orchestrator  : ${ORCHESTRATOR_MODEL}"
echo "  Worker model  : ${WORK_MODEL}"
echo "  Gateway token : ${OPENCLAW_TOKEN}"
echo ""

# ── 컨테이너 유지 ────────────────────────────────────────────────────────────
# SIGTERM 수신 시 openclaw 종료 후 컨테이너 정상 종료
# openclaw 가 죽으면 자동 재시작
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
        gosu node openclaw gateway &
        OPENCLAW_PID=$!
    fi
    sleep 3
done
