---
name: ollama_exec
description: Ollama 명령 실행 (모델 목록 조회, 다운로드, 상태 확인)
user-invocable: false
---

# 스킬: ollama-exec — Ollama 명령 실행

## 발동 조건

다음 상황에서 이 스킬을 사용한다:

- 설치된 모델 목록을 확인해야 할 때
- 사용 가능한 워커 모델을 확인해야 할 때
- 새 모델을 다운로드해야 할 때
- 현재 실행 중인 모델 상태를 확인해야 할 때
- `WORKER_MODEL` 환경변수에 어떤 모델이 설정됐는지 확인해야 할 때

---

## 핵심 원칙 (반드시 준수)

**`shell_execute` 도구를 실제로 호출해야 한다. 명령어를 텍스트로만 출력하는 것은 실행이 아니다.**

| 올바른 실행 | 금지 행동 |
|---|---|
| `shell_execute` 도구를 호출하여 실제 결과 반환 | 코드 블록 안에 명령어를 텍스트로 출력 |
| 도구가 반환한 결과를 그대로 사용 | 결과를 자체적으로 작성하거나 추측 |
| 실제 출력 형식과 다르면 재시도 | 출력 형식이 달라도 그냥 전달 |

---

## 명령어 목록

| 명령어 | 용도 |
|---|---|
| `ollama list` | 설치된 모델 전체 목록 조회 |
| `ollama ps` | 현재 메모리에 로드된 모델 확인 |
| `ollama show <모델명>` | 특정 모델 상세 정보 |
| `ollama pull <모델명>` | 모델 다운로드 |
| `echo $WORKER_MODEL` | 설정된 워커 모델 목록 확인 |
| `echo $ORCHESTRATOR_MODEL` | 오케스트레이터 모델 확인 |

---

## [1단계] shell_execute 도구 호출

shell MCP 서버의 `shell_execute` 도구를 호출한다. `command` 파라미터에 실행할 명령어 문자열을 전달한다.

- 모델 목록 조회: `command` = `"ollama list"`
- 환경변수 확인: `command` = `"echo \"Orchestrator=$ORCHESTRATOR_MODEL | Worker=$WORKER_MODEL\""`

**절대 금지 — 다음은 도구 실행이 아니다:**

- `ollama list 를 실행합니다.` 처럼 텍스트만 출력하고 기다리는 것
- `tool: shell_execute` / `command: "..."` 형태의 텍스트를 채팅창에 출력하는 것

반드시 `shell_execute` 도구를 실제로 호출해야 한다.

### [1단계] 완료 확인

다음 단계로 넘어가기 전 확인:

- [ ] `shell_execute` 도구를 **실제로 호출**했는가? (텍스트로 명령어를 출력한 것이 아닌가?)
- [ ] 도구 반환값이 터미널 실제 stdout인가? (내가 직접 작성한 결과가 아닌가?)

하나라도 NO → 처음으로 돌아가 `shell_execute`를 다시 호출한다.

---

## [2단계] 결과 검증

실제 `ollama list` 출력 형식:

```
NAME                    ID              SIZE      MODIFIED
qwen3:32b               abc123def456    20 GB     2 hours ago
gemma4:latest           789xyz012345    15 GB     3 hours ago
```

- 컬럼: `NAME`, `ID`, `SIZE`, `MODIFIED`
- ID는 12자리 16진수
- MODIFIED는 상대 시간 (`X hours ago`, `X days ago`)

**도구 결과가 위 형식과 다르면**: 도구를 제대로 호출하지 않은 것이다. 다시 `shell_execute`를 호출하라.  
**자체적으로 결과를 작성하는 것 금지**: 모르면 "도구 실행 실패"라고 보고한다.

### [2단계] 완료 확인

다음 단계로 넘어가기 전 확인:

- [ ] 출력값에 `NAME`, `ID`, `SIZE`, `MODIFIED` 컬럼이 있는가?
- [ ] 결과를 내가 수정하거나 보완하지 않았는가?

하나라도 NO → "도구 실행 실패"로 보고한다. 결과를 직접 만들어 내지 않는다.

---

## [3단계] Telegram 채팅창 출력

도구 실행 결과를 코드 블록으로 출력한다:

```
현재 설치된 Ollama 모델:

NAME                    ID              SIZE      MODIFIED
qwen3:32b               abc123def456    20 GB     2 hours ago
gemma4:latest           789xyz012345    15 GB     3 hours ago

총 2개 모델. 설정된 워커 모델: ollama/gemma4:latest
```

출력 후 필요한 경우 모델 선택 안내를 이어서 제공한다.

---

## 모델 다운로드

### 대용량 모델 (백그라운드 위임 권장)

```
sessions_spawn(
    task="ollama pull <모델명> 실행. 완료 시 '다운로드 완료: <모델명>' 보고",
    timeoutSeconds=1800
)
```

다운로드 시작 직후 채팅창에 알린다:
```
<모델명> 다운로드를 시작했습니다. 완료되면 알려드리겠습니다. (수 GB, 수 분~수십 분 소요)
```

### 소형 모델 (직접 실행 가능)

`shell_execute` 도구를 호출한다. `command` = `"ollama pull <모델명>"`

---

## 오류 처리

| 오류 메시지 | 원인 | 조치 |
|---|---|---|
| `connection refused` | Ollama 서버 미실행 | `ollama serve` 실행 후 재시도 |
| `model not found` | 잘못된 모델명 또는 태그 | `ollama list`로 정확한 이름 확인 |
| `no space left on device` | 디스크 공간 부족 | 사용자에게 공간 확보 요청 |
| `shell_execute` 응답 없음 | MCP 연결 문제 | `reload.sh` 실행 후 재시도 |

오류 발생 시 자체적으로 결과를 추측하지 말고 오류 내용을 그대로 사용자에게 보고한다.
