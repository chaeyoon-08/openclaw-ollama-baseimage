---
name: check_agents
description: 에이전트 현황 및 위임 이력 확인 (오케스트레이터/워커 모델별 작업 내역, cron 예약 작업)
user-invocable: true
---

# agent-status 스킬 — 오케스트레이션 현황 종합 확인

## 발동 조건

다음 중 하나에 해당하면 이 스킬을 실행한다:
- 사용자가 `/check-agents`, `/agent-status` 입력
- "서브 에이전트 작업 이력", "오케스트레이션 확인", "위임 현황", "에이전트 로그" 요청
- "예약 작업 목록", "cron 현황", "반복 작업 뭐 걸려 있어" 요청
- 작업 위임 후 결과가 제대로 처리됐는지 확인 요청

---

## 실행 절차

### [1단계] 오늘 로그에서 서브 에이전트 이벤트 추출

```bash
LOG_DATE=$(date +"%Y-%m-%d")
LOG_FILE="/tmp/openclaw-1000/openclaw-${LOG_DATE}.log"

if [ -f "$LOG_FILE" ]; then
    echo "=== 완료된 서브 에이전트 작업 ==="
    grep -E "완료:|res ✓ agent|llm-idle-timeout|\[diagnostic\].*timeout" "$LOG_FILE" 2>/dev/null || echo "(없음)"
    echo ""
    echo "=== 사용된 모델 ==="
    grep -E "agent model:|Worker model" "$LOG_FILE" 2>/dev/null | tail -5 || echo "(없음)"
    echo ""
    echo "=== 경고/오류 ==="
    grep -E "\[diagnostic\]|llm-idle-timeout|gateway request timeout|session-write-lock" "$LOG_FILE" 2>/dev/null | tail -10 || echo "(없음)"
else
    echo "오늘 로그 파일 없음 (아직 작업 없음)"
fi
```

### [2단계] 등록된 예약 작업(cron) 목록 조회

```bash
# openclaw.json에서 cron 잡 목록 읽기
jq '.crons // [] | .[] | {name: .name, schedule: .schedule, payload: .payload}' \
    /home/node/.openclaw/openclaw.json 2>/dev/null \
    || echo "(등록된 예약 작업 없음)"
```

```bash
# 환경변수에서 현재 모델 정보 확인
echo "ORCHESTRATOR=$ORCHESTRATOR_MODEL"
echo "WORKER_MODELS=$WORKER_MODELS"
```

### [3단계] 이력 파일 읽기

```bash
HISTORY_FILE="/home/node/.openclaw/workspace/AGENT_HISTORY.md"
if [ -f "$HISTORY_FILE" ]; then
    tail -40 "$HISTORY_FILE"
else
    echo "(이력 파일 없음)"
fi
```

### [4단계] 결과를 한 눈에 파악할 수 있는 형식으로 보고

아래 형식으로 정리한다. 기술 용어 없이, **각 작업마다 어떤 모델이 처리했는지** 반드시 표기한다.

모델 판단 기준:
- 로그에서 `완료:` 직전에 로드된 모델명 → 해당 완료 작업의 담당 모델
- `sessions_spawn`으로 위임된 작업 → 워커 모델 (WORKER_MODELS 첫 번째 항목)
- 오케스트레이터가 직접 처리한 작업 → ORCHESTRATOR_MODEL

```
에이전트 현황 — [날짜 시각]

──────────────────────────────
오케스트레이터: [모델명]
워커(서브 에이전트): [모델명 / 없으면 "오케스트레이터와 동일"]
──────────────────────────────

[오늘 위임 작업] 총 [N]건

  모델: [워커 모델명]
    ✓ [작업 내용] — [소요 시간, 있으면]
    ✓ [작업 내용]
    ✗ [실패한 작업 내용] — [실패 원인 한 줄]

  모델: [오케스트레이터 모델명]  ← 오케스트레이터가 직접 처리한 작업
    ✓ [작업 내용]

[주의 사항]
  - [있으면 기재 — 예: "응답 지연 1회 발생했으나 최종 완료됨"]
  - 없으면 "이상 없음"

──────────────────────────────
[등록된 예약 작업]

  [작업명] — 매 [주기]
    내용: [payload의 task 또는 kind 필드에서 추출]
    모델: [tier:local이면 ORCHESTRATOR_MODEL 값, 명시된 모델이 있으면 그 모델명]

  (없으면 "등록된 예약 작업 없음")
──────────────────────────────
```

### [5단계] AGENT_HISTORY.md 누적 기록 업데이트

오늘 날짜 섹션에 위임 작업 내역을 추가한다. `filesystem` MCP의 `read_file` + `write_file` 사용.

```markdown
## [YYYY-MM-DD]

| 시각 | 모델 | 작업 내용 | 결과 |
|---|---|---|---|
| [HH:MM] | [모델명] | [작업 내용] | 성공 / 실패 |
| [HH:MM] | [모델명] | [작업 내용] | 성공 / 실패 |
```

---

## 출력 원칙

- `sessions_spawn`, `KvSize`, `GPULayers` 등 내부 기술 용어를 사용자에게 노출하지 않는다
- 타임아웃·경고가 있어도 최종 성공했다면 "일시 지연이 있었으나 완료됨"으로 표현
- 실패한 작업이 있으면 원인을 한 줄로 설명한다 ("응답 초과로 중단됨", "모델 로딩 실패" 등)
- cron 잡의 payload가 복잡한 JSON이어도 핵심 의도만 한 문장으로 요약한다
