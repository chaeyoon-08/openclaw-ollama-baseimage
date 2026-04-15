# Ollama 스킬 가이드

## 이 폴더의 목적

Ollama 관련 작업 시 참조하는 스킬 파일 모음.
AGENTS.md에서 Ollama 작업이 필요할 때 이 폴더를 참조한다.

---

## 스킬 파일 목록

| 파일 | 용도 | 발동 조건 |
|---|---|---|
| `ollama-exec.md` | Ollama 명령 실행 | 모델 조회, 다운로드, 상태 확인, 환경변수 확인 |

---

## 스킬 파일 읽는 방법

shell MCP로 스킬 파일을 읽어 절차를 확인한다:

```
shell 도구 호출:
  명령어: cat /home/node/.openclaw/workspace/skills/ollama/ollama-exec.md
```

(filesystem MCP는 /workspace 만 서빙하므로 openclaw workspace 파일은 shell cat 사용)

---

## 상황별 참조 파일

| 상황 | 참조 파일 |
|---|---|
| `ollama list`, `ollama ps`, `ollama show` 실행 | `ollama-exec.md` |
| `ollama pull` 로 모델 다운로드 | `ollama-exec.md` — "모델 다운로드" 섹션 |
| Ollama 연결 오류 (`connection refused` 등) | `ollama-exec.md` — "오류 처리" 섹션 |
| 워커 모델 / 오케스트레이터 모델 환경변수 확인 | `ollama-exec.md` — "명령어 목록" 참조 |

---

## 스킬 실행 원칙

스킬 파일에 명시된 절차를 따를 때 반드시 지켜야 할 원칙:

1. **shell 도구를 실제로 호출한다** — 텍스트로 명령어만 출력하는 것은 실행이 아님
2. **도구 반환값을 그대로 사용한다** — 결과를 수정하거나 재작성하지 않음
3. **자체 생성 금지** — 도구를 호출하지 않고 결과를 만들어내는 것은 할루시네이션
