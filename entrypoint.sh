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
# 환경변수 선택: MODEL_API_KEY, NOTEBOOKLM_MCP_CLI_PATH, OPENCLAW_GATEWAY_TOKEN, GITHUB_*

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

log_ok "Required variables present"
log_ok "  ORCHESTRATOR_MODEL        = ${ORCHESTRATOR_MODEL}"
log_ok "  TELEGRAM_ALLOWED_USER_IDS = ${TELEGRAM_ALLOWED_USER_IDS}"

# ── 요금 폭탄 방어: 유료 Orchestrator → MODEL_API_KEY 확인 ──────────────────
if [ "$ORCH_PROVIDER" != "ollama" ]; then
    echo "$MODEL_API_KEY" | tr -s ' \t' '\n' | grep -v '^$' | grep -q "^${ORCH_PROVIDER}/" \
        || log_stop "ORCHESTRATOR_MODEL uses provider '${ORCH_PROVIDER}' but no matching MODEL_API_KEY entry found.
          Add MODEL_API_KEY=${ORCH_PROVIDER}/<your-api-key>"
fi

# Ollama 필요 여부 판단
NEEDS_OLLAMA=false
[ "$ORCH_PROVIDER" = "ollama" ] && NEEDS_OLLAMA=true

# WORKER_MODELS 중 ollama/ 항목이 있어도 Ollama 필요
if [ -n "$WORKER_MODELS" ]; then
    read -ra _WM_NEEDS_CHECK <<< "$WORKER_MODELS"
    for _wm_c in "${_WM_NEEDS_CHECK[@]}"; do
        [ "$(echo "$_wm_c" | cut -d'/' -f1)" = "ollama" ] && NEEDS_OLLAMA=true && break
    done
fi

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

    # 모델 존재 여부 확인: 이미 있으면 pull 건너뜀 (재시작 후 재다운로드 방지)
    _model_exists() {
        curl -sf http://localhost:11434/api/tags \
        | jq -r '.models[].name' 2>/dev/null \
        | grep -qxF "$1"
    }

    # 동기 pull — Orchestrator 모델: 봇 시작 전 반드시 준비 완료
    _pull_model() {
        local _model="$1"
        if _model_exists "$_model"; then
            log_ok "Model already present (skip): ${_model}"
            return 0
        fi
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
        # pull 후 실제 설치 여부 재확인
        # Ollama API는 registry 연결 실패 시에도 200 반환하는 경우 있음 → 오탐 방지
        if ! _model_exists "$_model"; then
            log_stop "Model pull failed: '${_model}' not found after pull. Check network connectivity to registry.ollama.ai"
        fi
        log_ok "Model ready: ${_model}"
    }

    # Orchestrator 모델 pull (ollama 모델일 때만) — 동기
    if [ "$ORCH_PROVIDER" = "ollama" ]; then
        ORCH_MODEL_NAME=$(echo "$ORCHESTRATOR_MODEL" | cut -d'/' -f2-)
        _pull_model "$ORCH_MODEL_NAME"
    fi

    # Worker 모델 pull (WORKER_MODELS 환경변수, 공백 구분)
    # 포맷: "ollama/gemma4:31b ollama/gemma4:e2b"
    # 이미 볼륨에 있으면 "Model already present (skip)" — 재다운로드 없이 즉시 기동
    if [ -n "$WORKER_MODELS" ]; then
        read -ra _WM_ENTRIES <<< "$WORKER_MODELS"
        for _wm_entry in "${_WM_ENTRIES[@]}"; do
            _wm_provider=$(echo "$_wm_entry" | cut -d'/' -f1)
            _wm_name=$(echo "$_wm_entry" | cut -d'/' -f2-)
            if [ "$_wm_provider" = "ollama" ]; then
                _pull_model "$_wm_name"
            else
                log_info "Worker model '${_wm_entry}' is not an Ollama model — skipping pull"
            fi
        done
    fi

    # 런타임 모델 추가: 봇에게 요청 → ollama pull → restart.sh(gateway full restart)
    # restart.sh 실행 시 /api/tags 재스캔 → /models에 자동 반영
    # Source: https://github.com/openclaw/openclaw/issues/49568
else
    log_info "Ollama not required — skipping Ollama start"
fi

# ── 5. node 사용자 디렉터리 권한 설정 ───────────────────────────────────────
# root 단계에서 먼저 수행 (gosu 이후에는 chown 불가)
log_start "Setting up node user environment"

chown -R node:node /home/node/.openclaw

# NOTEBOOKLM_MCP_CLI_PATH 마운트 경로 처리
# nlm login CLI는 ~/.notebooklm-mcp-cli/ 에 고정 저장하므로
# gcube 마운트 경로로 심링크 → 컨테이너 재시작 후에도 auth 유지
# Source: https://github.com/jacob-bd/notebooklm-mcp-cli/blob/main/docs/AUTHENTICATION.md
NLM_HOME="${NOTEBOOKLM_MCP_CLI_PATH:-/mnt/notebooklm/OpenClaw_Auth}"
export NOTEBOOKLM_MCP_CLI_PATH="$NLM_HOME"

if [ -d "$NLM_HOME" ]; then
    chown -R node:node "$NLM_HOME" 2>/dev/null || true
    rm -rf /home/node/.notebooklm-mcp-cli
    ln -s "$NLM_HOME" /home/node/.notebooklm-mcp-cli
    log_ok "NOTEBOOKLM_MCP_CLI_PATH: ${NLM_HOME} (symlinked)"
else
    log_warn "NOTEBOOKLM_MCP_CLI_PATH not mounted: ${NLM_HOME}"
    log_warn "  nlm login will use container-local storage (not persistent)"
fi

# ── 6. workspace 템플릿 복사 ────────────────────────────────────────────────
log_start "Copying workspace templates"
WORKSPACE="/home/node/.openclaw/workspace"
mkdir -p "$WORKSPACE"

# 시스템 지침 파일: 기본값은 재배포마다 이미지 버전으로 갱신
# .custom 마커 파일이 있으면 사용자가 직접 편집한 버전을 유지 (덮어쓰기 건너뜀)
# 마커 파일 생성: touch $WORKSPACE/.custom
# 마커 파일 삭제 후 재시작: 이미지 기본값으로 복원
_copy_system_template() {
    local src="$1" dst="$2"
    if [ -f "$WORKSPACE/.custom" ]; then
        log_info "User .custom marker found — preserving: $(basename "$dst")"
    else
        cp "$src" "$dst"
    fi
}
_copy_system_template /templates/AGENTS.md      "$WORKSPACE/AGENTS.md"
_copy_system_template /templates/CONSTRAINTS.md "$WORKSPACE/CONSTRAINTS.md"
_copy_system_template /templates/TOOLS.md       "$WORKSPACE/TOOLS.md"

# 스킬 디렉토리: 재배포마다 최신 이미지 버전으로 갱신 (.custom 적용 안 함)
if [ -d "/templates/skills" ]; then
    rm -rf "$WORKSPACE/skills"
    cp -r /templates/skills "$WORKSPACE/skills"
    log_ok "Skills directory updated (skills/)"
fi

if [ -f "$WORKSPACE/.custom" ]; then
    log_info "System templates preserved (user .custom active)"
else
    log_ok "System templates updated (AGENTS.md, CONSTRAINTS.md, TOOLS.md)"
fi

# 사용자 데이터 파일: MEMORY.md를 sentinel로 최초 실행 여부 판단
# MEMORY.md, SOUL.md는 에이전트가 축적한 기억/성격 → 절대 덮어쓰지 않음
# MODEL_GUIDE.md: 모델 특성 가이드 — 에이전트가 채워넣으므로 최초 1회만 복사
if [ ! -f "$WORKSPACE/MEMORY.md" ]; then
    log_ok "First run detected — initializing user data from templates"
    cp /templates/SOUL.md        "$WORKSPACE/SOUL.md"
    cp /templates/MEMORY.md      "$WORKSPACE/MEMORY.md"
    cp /templates/MODEL_GUIDE.md "$WORKSPACE/MODEL_GUIDE.md"
else
    log_info "User data preserved (MEMORY.md, SOUL.md, MODEL_GUIDE.md)"
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
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_ALLOWED_USER_IDS="${TELEGRAM_ALLOWED_USER_IDS}"
ORCHESTRATOR_MODEL="${ORCHESTRATOR_MODEL}"

# 선택: 워커 모델 목록 (공백 구분, provider/model:tag 포맷)
# 시작 시 자동 pull, subagents.model.primary로 등록됨 (첫 번째 항목)
# 예: WORKER_MODELS="ollama/gemma4:31b ollama/gemma4:e2b"
WORKER_MODELS="${WORKER_MODELS:-}"

# 선택: 외부 provider API 키 (provider/key 형식, 공백으로 여러 개)
MODEL_API_KEY="${MODEL_API_KEY:-}"

# 선택: Gateway 토큰 (미설정 시 자동 생성, 설정 시 재시작 후에도 유지)
OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"

# 선택: NotebookLM 인증 경로 (Dropbox 마운트 경로)
NOTEBOOKLM_MCP_CLI_PATH="${NLM_HOME}"

# 선택: GitHub
GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_EMAIL="${GITHUB_EMAIL:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_REPO_URL="${GITHUB_REPO_URL:-}"
ENVEOF
chmod 600 "$ENV_FILE"
chown node:node "$ENV_FILE"
log_ok ".env written: ${ENV_FILE}"

# ── 8. openclaw.json 생성 (generate-config.sh 호출) ─────────────────────────
# openclaw.json 항상 재생성: anomaly 상태 제거 → full scope fresh pairing 보장
# token은 generate-config.sh가 기존 파일에서 먼저 읽어 유지함
# devices/ 클리어: operator.read로 고정된 pairing 레코드 제거 → fresh pairing 강제
CONFIG_FILE="/home/node/.openclaw/openclaw.json"
rm -rf /home/node/.openclaw/devices 2>/dev/null || true
rm -f  /home/node/.openclaw/openclaw.json.bak 2>/dev/null || true
bash /usr/local/bin/generate-config.sh
chown node:node "$CONFIG_FILE"
OPENCLAW_TOKEN=$(jq -r '.gateway.auth.token' "$CONFIG_FILE")

# ── 9. Stale session lock 파일 정리 ─────────────────────────────────────────
# 컨테이너 재시작 시 이전 인스턴스 PID는 무효화됨 → .lock 파일이 잔류하면
# 새 세션 요청이 "session file locked (timeout 10000ms)"으로 전부 실패
# Source: https://github.com/openclaw/openclaw/issues/27252
_STALE_LOCKS=$(find /home/node/.openclaw/agents -name "*.lock" 2>/dev/null || true)
if [ -n "$_STALE_LOCKS" ]; then
    _LOCK_COUNT=$(echo "$_STALE_LOCKS" | wc -l)
    find /home/node/.openclaw/agents -name "*.lock" -delete 2>/dev/null || true
    log_ok "Cleaned ${_LOCK_COUNT} stale session lock file(s)"
else
    log_info "No stale session lock files"
fi

# ── 10. OpenClaw gateway 시작 (node 사용자로 실행) ───────────────────────────
# Source: https://docs.openclaw.ai/cli/gateway
# gosu로 root → node 전환하여 보안 실행
log_start "Starting OpenClaw gateway"

export OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_TOKEN}"
# OPENCLAW_NO_RESPAWN=1: SIGUSR1 수신 시 새 프로세스 spawn 대신 in-process 재시작
# 커스텀 supervisor(entrypoint while 루프) 환경에서 이중 인스턴스 → EADDRINUSE 방지
# Source: https://github.com/openclaw/openclaw/issues/65668
export OPENCLAW_NO_RESPAWN=1
gosu node openclaw gateway &
OPENCLAW_PID=$!

sleep 3

log_done "All services started"
echo ""
echo "  Orchestrator  : ${ORCHESTRATOR_MODEL}"
[ -n "$WORKER_MODELS" ] && echo "  Worker Models : ${WORKER_MODELS}"
echo "  Gateway token : ${OPENCLAW_TOKEN}"
echo ""

# ── 컨테이너 유지 ────────────────────────────────────────────────────────────
# SIGTERM 수신 시 openclaw 종료 후 컨테이너 정상 종료
# openclaw 가 죽으면 자동 재시작 (단, SIGUSR1 자체 재시작은 PID 추적만 갱신)
_stop() {
    log_warn "Shutting down..."
    kill "$OPENCLAW_PID" 2>/dev/null
    exit 0
}
trap _stop SIGTERM SIGINT

while true; do
    if ! kill -0 "$OPENCLAW_PID" 2>/dev/null; then
        # PID 사라짐 — 게이트웨이가 SIGUSR1 자체 재시작했는지 확인
        sleep 2
        NEW_PID=$(pgrep -u node -f "openclaw-gateway" 2>/dev/null | head -1 || true)
        if [ -n "$NEW_PID" ]; then
            # 자체 재시작: 새 PID 추적만 갱신, 재시작 시도 금지 (포트 충돌 방지)
            log_info "Gateway self-restarted (new PID: ${NEW_PID}) — tracking updated"
            OPENCLAW_PID="$NEW_PID"
        else
            log_warn "OpenClaw gateway stopped, restarting..."
            gosu node openclaw gateway &
            OPENCLAW_PID=$!
        fi
    fi
    sleep 3
done
