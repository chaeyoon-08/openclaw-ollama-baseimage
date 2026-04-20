---
name: nlm_login
description: NotebookLM MCP 인증 만료 시 gcube 서버에서 직접 재인증
user-invocable: true
---

# 스킬: nlm-login — NotebookLM 재인증

## 발동 조건

다음 중 하나에 해당하면 이 스킬을 실행한다:
- NLM 도구 호출 시 인증 오류 (auth expired, unauthorized, cookie error)
- 사용자가 `/nlm_login` 입력 또는 NLM 재인증 요청

---

## 실행 순서 — 반드시 이 순서대로

### [1단계] noVNC + nlm login 프로세스 시작

`shell_execute` 도구로 실행:

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

`shell_execute` 도구로 실행:

```bash
bash /usr/local/bin/nlm-reauth-finish.sh
```

### [4단계] NLM MCP 재연결을 위해 gateway reload

`shell_execute` 도구로 실행:

```bash
bash /usr/local/bin/reload.sh
```

### [5단계] 완료 안내

```
NotebookLM 인증이 갱신됐습니다. NLM 도구를 다시 사용할 수 있습니다.
```

---

## 오류 처리

`nlm-reauth-finish.sh` 실행 후 "Auth file not found" 메시지가 나오면:
1. `shell_execute`로 `/tmp/nlm-login.log` 내용을 읽어 사용자에게 보고
2. 재시도 여부를 확인한다
