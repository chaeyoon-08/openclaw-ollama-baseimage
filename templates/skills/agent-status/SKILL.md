---
name: check_agents
description: 에이전트 현황 및 위임 이력 확인 (오케스트레이터/워커 모델별 작업 내역, cron 예약 작업)
user-invocable: true
---

# check_agents — 에이전트 현황 확인

## 발동 조건

- 사용자가 `/check_agents` 입력
- "서브 에이전트 이력", "위임 현황", "예약 작업(cron) 목록", "사용 모델 확인" 요청

---

## 절차

### [1] 모델 및 cron 현황

`shell_execute`로 실행:

```bash
jq -r '"오케스트레이터: " + .agents.defaults.model.primary + "\n워커: " + (.agents.defaults.subagents.model.primary // "없음") + "\n\n[cron 목록]" + (if (.crons // [] | length) == 0 then "\n  (없음)" else (.crons[] | "\n  - " + .name + " (" + .schedule + ")") end)' /home/node/.openclaw/openclaw.json 2>/dev/null || echo "config 읽기 실패"
```

### [2] 오늘 에이전트 활동 로그

`shell_execute`로 실행:

```bash
grep -oE '"agent model:[^"]+"|"spawn[^"]*"|embedded run (timeout|failover)|complete[^"]*"' \
  /tmp/openclaw-1000/openclaw-$(date +%Y-%m-%d).log 2>/dev/null | tail -15 || echo "오늘 활동 없음"
```

### [3] 결과 보고

위 두 결과를 바탕으로 아래를 간결하게 답한다:
- 현재 오케스트레이터 / 워커 모델
- 오늘 위임 작업 요약 (있으면)
- 등록된 cron 목록 (없으면 "없음")
