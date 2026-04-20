#!/bin/bash
# apply-model-config.sh — add_model.json 읽어서 .env 갱신 후 gateway 재설정
#
# 사용법: /add_model 슬래시 커맨드로 호출
# 설정 파일: /home/node/.openclaw/add_model.json
#
# add_model.json 지원 필드:
#   ollama_add  : Ollama 모델 태그 배열 (예: ["gemma4:31b"])
#   api_keys    : provider→key 객체 (예: {"anthropic": "sk-ant-..."})

set -e

CONFIG="/home/node/.openclaw/add_model.json"
ENV_FILE="/home/node/.openclaw/.env"

# ── 로그 함수 ──────────────────────────────────────────────────────────────────
log_doing() { echo -e "\033[0;36m[ DOING ]\033[0m $1"; }
log_ok()    { echo -e "\033[0;32m[  OK   ]\033[0m $1"; }
log_info()  { echo -e "\033[0;37m[ INFO  ]\033[0m $1"; }
log_warn()  { echo -e "\033[1;33m[ WARN  ]\033[0m $1"; }
log_stop()  { echo -e "\033[1;31m[ STOP  ]\033[0m $1"; exit 1; }
log_done()  { echo -e "\033[1;32m[ DONE  ]\033[0m $1"; }

# ── 파일 존재 확인 ─────────────────────────────────────────────────────────────
[ ! -f "$CONFIG" ]   && log_stop "add_model.json 없음: ${CONFIG}"
[ ! -f "$ENV_FILE" ] && log_stop ".env 없음: ${ENV_FILE}"

# ── 적용 항목 파싱 ─────────────────────────────────────────────────────────────
OLLAMA_MODELS=$(jq -r '.ollama_add // [] | .[]' "$CONFIG" 2>/dev/null \
    | grep -v '^$' || true)
API_KEY_ENTRIES=$(jq -r \
    '.api_keys // {} | to_entries[]
     | select(.value != "" and .value != null)
     | "\(.key)/\(.value)"' \
    "$CONFIG" 2>/dev/null | grep -v '^$' || true)

# ── 변경사항 없으면 조기 종료 ─────────────────────────────────────────────────
if [ -z "$OLLAMA_MODELS" ] && [ -z "$API_KEY_ENTRIES" ]; then
    log_info "적용할 항목 없음 — add_model.json을 편집 후 다시 실행하세요"
    log_info "  파일 위치: ${CONFIG}"
    exit 0
fi

# ── .env 키 업데이트 함수 ─────────────────────────────────────────────────────
_env_update() {
    local key="$1" val="$2"
    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$ENV_FILE"
    else
        echo "${key}=\"${val}\"" >> "$ENV_FILE"
    fi
}

# ── Ollama 모델 처리 ──────────────────────────────────────────────────────────
if [ -n "$OLLAMA_MODELS" ]; then
    CURRENT_WM=$(grep "^WORKER_MODELS=" "$ENV_FILE" \
        | sed 's/^WORKER_MODELS="\(.*\)"/\1/' | tr -s ' ' || true)

    for model in $OLLAMA_MODELS; do
        # ollama/ 접두사 보정
        [[ "$model" != ollama/* ]] && model="ollama/${model}"
        MODEL_NAME="${model#ollama/}"

        # 중복 등록 방지
        if echo " ${CURRENT_WM} " | grep -qF " ${model} "; then
            log_info "이미 등록됨 (skip): ${model}"
            continue
        fi

        # Ollama 실행 여부 확인
        if ! curl -sf http://127.0.0.1:11434/ > /dev/null 2>&1; then
            log_warn "Ollama 미실행 — ${MODEL_NAME} pull 생략, WORKER_MODELS에만 등록"
        else
            # 이미 로컬에 있으면 pull 생략
            if curl -sf http://127.0.0.1:11434/api/tags \
               | jq -r '.models[].name' 2>/dev/null \
               | grep -qxF "$MODEL_NAME"; then
                log_ok "모델 이미 존재 (pull 생략): ${MODEL_NAME}"
            else
                log_doing "모델 다운로드 중: ${MODEL_NAME}"
                _LAST_BUCKET=-1
                curl -sf -X POST http://127.0.0.1:11434/api/pull \
                    -d "{\"name\":\"${MODEL_NAME}\"}" \
                | while IFS= read -r line; do
                    STATUS=$(printf '%s' "$line" | jq -r '.status    // empty' 2>/dev/null)
                    TOTAL=$( printf '%s' "$line" | jq -r '.total     // 0'     2>/dev/null)
                    DONE=$(  printf '%s' "$line" | jq -r '.completed // 0'     2>/dev/null)
                    if [ "${TOTAL:-0}" -gt 0 ] 2>/dev/null; then
                        PCT=$(( DONE * 100 / TOTAL ))
                        BUCKET=$(( PCT / 10 * 10 ))
                        [ "$BUCKET" -ne "$_LAST_BUCKET" ] \
                            && _LAST_BUCKET=$BUCKET \
                            && log_doing "  ${STATUS}: ${BUCKET}%"
                    elif [ -n "$STATUS" ]; then
                        case "$STATUS" in
                            "pulling manifest"|"verifying sha256 digest"|"writing manifest"|"success")
                                log_doing "  ${STATUS}" ;;
                        esac
                    fi
                done

                # pull 실패 확인
                if ! curl -sf http://127.0.0.1:11434/api/tags \
                   | jq -r '.models[].name' 2>/dev/null \
                   | grep -qxF "$MODEL_NAME"; then
                    log_warn "pull 실패: ${MODEL_NAME} — WORKER_MODELS 등록은 진행"
                fi
            fi
        fi

        # WORKER_MODELS에 추가
        CURRENT_WM="${CURRENT_WM} ${model}"
        CURRENT_WM=$(echo "$CURRENT_WM" | tr -s ' ' | sed 's/^ //')
        log_ok "WORKER_MODELS 등록: ${model}"
    done

    _env_update "WORKER_MODELS" "$CURRENT_WM"
fi

# ── API 키 처리 ───────────────────────────────────────────────────────────────
if [ -n "$API_KEY_ENTRIES" ]; then
    CURRENT_KEYS=$(grep "^MODEL_API_KEY=" "$ENV_FILE" \
        | sed 's/^MODEL_API_KEY="\(.*\)"/\1/' | tr -s ' ' || true)

    for entry in $API_KEY_ENTRIES; do
        provider=$(echo "$entry" | cut -d'/' -f1)

        # 같은 provider 기존 항목 교체
        CURRENT_KEYS=$(echo " ${CURRENT_KEYS} " \
            | tr ' ' '\n' | grep -v "^${provider}/" | grep -v '^$' \
            | tr '\n' ' ' | tr -s ' ' | sed 's/^ //')
        CURRENT_KEYS="${CURRENT_KEYS} ${entry}"
        CURRENT_KEYS=$(echo "$CURRENT_KEYS" | tr -s ' ' | sed 's/^ //')

        log_ok "API 키 등록: ${provider}"
    done

    _env_update "MODEL_API_KEY" "$CURRENT_KEYS"
fi

# ── add_model.json 초기화 (구조 유지, 값만 비움) ────────────────────────────
jq '.ollama_add = [] | .api_keys = {}' "$CONFIG" > /tmp/add_model_reset.json \
    && mv /tmp/add_model_reset.json "$CONFIG"
log_ok "add_model.json 초기화 (재사용 가능)"

# ── gateway 재설정 ────────────────────────────────────────────────────────────
log_doing "설정 갱신 중..."
bash /usr/local/bin/reload.sh

log_done "모델/키 적용 완료"
