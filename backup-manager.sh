#!/bin/bash
# backup-manager.sh — OpenClaw workspace 백업/복원 관리
#
# 사용법:
#   backup-manager.sh list              — 백업 목록 조회
#   backup-manager.sh save [name]       — 수동 백업 생성
#   backup-manager.sh restore <name>    — 백업 복원 후 gateway 재시작
#
# 백업 위치: /data/data/backups/
#   manual/  — 사용자 요청 백업 (무제한)
#   temp/    — 자동 임시 백업 (최대 5개, entrypoint.sh auto-save 루프가 관리)
#
# 이름 규칙:
#   수동 백업 (이름 지정)  : 사용자 지정 이름 (예: my-settings)
#   수동 백업 (이름 미지정): YYYYMMDD-HHmm (예: 20260401-1430)
#   임시 백업 (자동)       : temp-YYYYMMDD-HHmm (예: temp-20260401-1430)

WORKSPACE_DIR="/root/.openclaw/workspace"
STORAGE_PATH="${STORAGE_PATH:-/mnt/storage}"
MANUAL_BACKUP_DIR="${STORAGE_PATH}/backups/manual"
TEMP_BACKUP_DIR="${STORAGE_PATH}/backups/temp"

log_ok()    { echo -e "\033[0;32m[  OK   ]\033[0m $1"; }
log_doing() { echo -e "\033[0;36m[ DOING ]\033[0m $1"; }
log_done()  { echo -e "\033[1;32m[ DONE  ]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ ERROR ]\033[0m $1"; }
log_info()  { echo -e "\033[0;37m[ INFO  ]\033[0m $1"; }

_check_cloud() {
    if [ ! -d "$STORAGE_PATH" ]; then
        log_error "Cloud storage not mounted (${STORAGE_PATH}). Backup features unavailable."
        log_error "gcube Storage Management에서 저장소를 연결하고 STORAGE_PATH 환경변수를 설정하세요."
        exit 1
    fi
}

cmd_list() {
    _check_cloud
    echo ""
    echo "  Manual backups:"
    if [ -z "$(ls "$MANUAL_BACKUP_DIR" 2>/dev/null)" ]; then
        echo "    (없음)"
    else
        ls -t "$MANUAL_BACKUP_DIR" | while read -r _name; do
            echo "    [manual] $_name"
        done
    fi
    echo ""
    echo "  Temp backups (auto-save, max 5):"
    if [ -z "$(ls "$TEMP_BACKUP_DIR" 2>/dev/null)" ]; then
        echo "    (없음)"
    else
        ls -t "$TEMP_BACKUP_DIR" | while read -r _name; do
            echo "    [temp] $_name"
        done
    fi
    echo ""
}

cmd_save() {
    _check_cloud
    _NAME="${1:-$(date '+%Y%m%d-%H%M')}"
    _DST="$MANUAL_BACKUP_DIR/$_NAME"
    if [ -d "$_DST" ]; then
        log_error "이미 존재하는 백업 이름: $_NAME"
        exit 1
    fi
    mkdir -p "$_DST"
    log_doing "Saving workspace to manual/$_NAME"
    cp -r "${WORKSPACE_DIR}/." "$_DST/"
    log_done "Saved: manual/$_NAME"
}

cmd_restore() {
    _check_cloud
    _NAME="$1"
    if [ -z "$_NAME" ]; then
        log_error "복원할 백업 이름을 지정하세요."
        log_info "  backup-manager.sh list 로 목록 확인 후 사용하세요."
        exit 1
    fi
    # manual 또는 temp 중에서 찾기
    if [ -d "$MANUAL_BACKUP_DIR/$_NAME" ]; then
        _SRC="$MANUAL_BACKUP_DIR/$_NAME"
    elif [ -d "$TEMP_BACKUP_DIR/$_NAME" ]; then
        _SRC="$TEMP_BACKUP_DIR/$_NAME"
    else
        log_error "백업을 찾을 수 없습니다: $_NAME"
        log_info "  backup-manager.sh list 로 목록을 확인하세요."
        exit 1
    fi
    log_doing "Restoring from $_SRC"
    mkdir -p "$WORKSPACE_DIR"
    cp -r "${_SRC}/." "$WORKSPACE_DIR/"
    log_done "Restored from $_NAME"
    log_doing "Restarting OpenClaw gateway..."
    pkill -f openclaw-gateway 2>/dev/null || true
    log_info "(잠시 후 자동으로 재시작됩니다)"
}

case "$1" in
    list)    cmd_list ;;
    save)    cmd_save "$2" ;;
    restore) cmd_restore "$2" ;;
    *)
        echo ""
        echo "  Usage: backup-manager.sh <command>"
        echo ""
        echo "  Commands:"
        echo "    list              — 백업 목록 조회"
        echo "    save [name]       — 수동 백업 생성 (이름 생략 시 타임스탬프 자동)"
        echo "    restore <name>    — 백업 복원 후 gateway 재시작"
        echo ""
        exit 1
        ;;
esac
