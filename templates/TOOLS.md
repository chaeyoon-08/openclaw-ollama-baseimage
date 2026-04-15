# TOOLS.md — 사용 가능한 도구 가이드

## MCP 서버 도구

### NotebookLM (notebooklm)

지식 검색 및 리서치의 1순위 도구. 코드 작성 전 반드시 먼저 사용하라.

**사용 원칙:**
- 새로운 라이브러리, API, 설정 방법이 필요할 때 반드시 먼저 조회
- 1회 조회로 불충분하면 후속 질문을 반복하여 완전한 맥락 확보
- 내부 지식만으로 판단하지 말 것 — 할루시네이션 방지

**주요 도구:**

| 도구 | 용도 |
|---|---|
| `notebooklm_query` | 노트북에서 정보 검색 및 질의 |
| `notebooklm_list_notebooks` | 사용 가능한 노트북 목록 조회 |
| `notebooklm_get_sources` | 노트북의 소스 문서 목록 조회 |

**사용 예시:**
```
"OpenClaw의 sessions_spawn 사용법을 찾아줘"
→ notebooklm_query("OpenClaw sessions_spawn multi-agent orchestration")
→ 결과 불충분 시 → notebooklm_query("OpenClaw subagent spawn depth configuration")
→ 충분한 맥락 확보 후 코드 작성
```

---

### Filesystem (filesystem)

/workspace 디렉터리의 파일을 직접 읽고 분석한다.

| 도구 | 용도 |
|---|---|
| `read_file` | 파일 내용 읽기 |
| `list_directory` | 디렉터리 구조 조회 |
| `search_files` | 파일 내용 검색 |
| `write_file` | 파일 작성/수정 |

---

## 빌트인 도구

### 웹 검색 (web_search)

NotebookLM에 없는 최신 정보나 외부 자료 검색 시 사용.

```
web_search("OpenClaw 2026 changelog latest features")
```

---

## 멀티 에이전트 도구

### sessions_spawn — 서브 에이전트 생성

복잡하거나 오래 걸리는 작업을 백그라운드에서 병렬로 처리한다.

```
sessions_spawn(
    task="[구체적인 작업 내용]",
    timeoutSeconds=300
)
```

**제약사항:**
- 최대 깊이(maxSpawnDepth): 1 — 서브 에이전트는 추가 서브 에이전트를 생성하지 않음
- Telegram 채널에서 동작 확인됨 (depth=1 한정)
- 완료 후 결과가 현재 채널에 자동 반환됨

### sessions_send — 세션 간 메시지

```
sessions_send(
    sessionKey="[대상 세션 키]",
    message="[메시지]",
    timeoutSeconds=60
)
```

### sessions_list — 활성 세션 목록

현재 실행 중인 세션을 확인한다.

---

## 플러그인 설치

부족한 기능이 있으면 스스로 설치한다:

```bash
openclaw plugins install [패키지명]
# 설치 후 gateway 재시작 필요
bash /usr/local/bin/reload.sh
```

---

## 스킬: ollama-exec

Ollama 명령 실행이 필요할 때 사용하는 스킬. shell MCP 도구를 통해 실행하고 결과를 채팅창에 전달한다.

**발동 조건:** 모델 목록 조회, 모델 다운로드, 상태 확인, 환경변수 확인 등 모든 Ollama 관련 명령 실행 시.

**핵심 원칙:** shell 도구를 실제로 호출해야 한다. 명령어를 텍스트로만 출력하는 것은 실행이 아니다.

**상세 절차:** `skills/ollama/ollama-exec.md` 참조  
**추가 지침:** `skills/ollama/GUIDE.md` 참조

---

## 스킬: nlm-login

NotebookLM MCP 인증이 만료되었을 때 gcube 서버에서 직접 재인증하는 스킬.

**발동 조건:** NLM 도구 호출 시 인증 오류(auth expired, unauthorized, cookie error), 또는 사용자가 NLM 재인증 요청.

**실행 순서 — 반드시 이 순서대로:**

### [1단계] noVNC + nlm login 프로세스 시작

```bash
bash /usr/local/bin/nlm-reauth-start.sh
```

### [2단계] 사용자에게 안내 전송

```
NotebookLM 재인증 준비됐습니다.
SSH 터널을 열고 브라우저에서 Google 로그인을 진행해 주세요.

1. [로컬 PC 터미널 새 창] SSH 터널 연결:
   ssh -p <SSH접속포트> -L 6080:localhost:6080 <사용자아이디>@entry.gcube.ai
   (gcube 포털 → 워크로드 → SSH 접속 정보에서 포트/아이디/비밀번호 확인)

2. [로컬 브라우저] http://localhost:6080/vnc.html 접속

3. 화면에서 Google 계정으로 로그인

4. 로그인 완료 후 이 채팅에 "완료"라고 입력해 주세요.
```

### [3단계] 사용자가 "완료"라고 하면 — 인증 파일 저장 + 정리

```bash
bash /usr/local/bin/nlm-reauth-finish.sh
```

### [4단계] NLM MCP 재연결을 위해 gateway reload

```bash
bash /usr/local/bin/reload.sh
```

### [5단계] 완료 안내

```
NotebookLM 인증이 갱신됐습니다. NLM 도구를 다시 사용할 수 있습니다.
```

**오류 처리:** `nlm-reauth-finish.sh` 실행 후 "Auth file not found" 메시지가 나오면 `/tmp/nlm-login.log` 내용을 사용자에게 보고하고 재시도 여부를 확인한다.
