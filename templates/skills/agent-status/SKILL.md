# agent-status 스킬 — 오케스트레이션 이력 확인

## 발동 조건

다음 중 하나에 해당하면 이 스킬을 실행한다:
- 사용자가 `/check-agents`, `/agent-status` 입력
- "서브 에이전트 작업 이력", "오케스트레이션 확인", "위임 현황", "에이전트 로그" 등 요청
- 작업 위임 후 결과가 제대로 처리됐는지 확인 요청

---

## 실행 절차

### [1단계] 오늘 날짜 확인

```bash
date +"%Y-%m-%d"
```

### [2단계] OpenClaw 로그에서 서브 에이전트 이벤트 추출

```bash
LOG_DATE=$(date +"%Y-%m-%d")
LOG_FILE="/tmp/openclaw-1000/openclaw-${LOG_DATE}.log"

if [ -f "$LOG_FILE" ]; then
    echo "=== 완료된 서브 에이전트 작업 ==="
    grep -E "완료:|res ✓ agent|llm-idle-timeout|diagnostic.*timeout|sessions_spawn" "$LOG_FILE" 2>/dev/null || echo "(없음)"
    echo ""
    echo "=== 사용된 모델 ==="
    grep -E "agent model:|starting runner.*model" "$LOG_FILE" 2>/dev/null | tail -20 || echo "(없음)"
    echo ""
    echo "=== 경고/오류 ==="
    grep -E "WARN|ERROR|\[diagnostic\]|timeout|failed|error" "$LOG_FILE" 2>/dev/null | grep -v "cpu_linux\|GGML\|NVML\|compile" | tail -20 || echo "(없음)"
else
    echo "오늘 로그 파일 없음: $LOG_FILE"
fi
```

### [3단계] 이력 파일 읽기 (이전 세션 누적 기록)

```bash
HISTORY_FILE="/home/node/.openclaw/workspace/AGENT_HISTORY.md"
if [ -f "$HISTORY_FILE" ]; then
    tail -60 "$HISTORY_FILE"
else
    echo "(이력 파일 없음 — 아직 기록된 위임 작업 없음)"
fi
```

### [4단계] 결과를 사람이 읽기 쉬운 형식으로 요약하여 보고

로그 파싱 결과를 바탕으로 아래 형식으로 보고한다. **기술 용어 없이** 작성한다.

```
오케스트레이션 현황 — [날짜]

오늘 위임한 작업: [N]건
[작업 목록 — "완료:" 행에서 추출, 성공/실패 표기]

사용된 모델:
  오케스트레이터: [모델명]
  서브 에이전트: [모델명]

주의 사항: [있으면 기재, 없으면 "이상 없음"]
```

### [5단계] AGENT_HISTORY.md 업데이트

오늘 날짜 섹션이 없으면 추가한다. `filesystem` MCP의 `write_file` 또는 `read_file` + `write_file` 조합으로 처리.

```
## [날짜]

| 시각 | 작업 내용 | 모델 | 결과 |
|---|---|---|---|
| [시각] | [작업 내용] | [모델] | 성공/실패 |
```

---

## 출력 원칙

- "sessions_spawn", "KvSize", "GPULayers" 등 기술 용어를 사용자에게 그대로 노출하지 않는다
- 타임아웃이나 경고가 있어도 최종 성공했다면 "일시 지연이 있었으나 완료됨"으로 표현
- 실패한 작업이 있으면 구체적으로 어떤 작업이 실패했는지 명시
