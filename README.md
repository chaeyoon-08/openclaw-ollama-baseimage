# openclaw-mcp-hub

외부 서비스 인증이 필요한 MCP 서버 전용 컨테이너 이미지.
OpenClaw main 컨테이너(`openclaw-bot-multi`)와 동일 Pod 내에서 동작하며, `localhost`를 통해 MCP 서버를 제공한다.

| 브랜치 | 이미지 | 태그 |
|---|---|---|
| `mcp-hub` | `ghcr.io/chaeyoon-08/openclaw-mcp-hub` | `:latest`, `:sha-<7자>` |

---

## 역할

```
gcube 워크로드 (동일 Pod)
├── openclaw-bot-multi   OpenClaw + Ollama (main)
│     MCP 연결 → localhost:3100/sse
│
└── openclaw-mcp-hub     이 이미지
      ├── notebooklm MCP (SSE, port 3100)
      └── noVNC (port 6080, 재인증 시 기동)
```

main 컨테이너에서 MCP 서버를 직접 실행하지 않고 이 컨테이너에 위임함으로써:
- 인증 파일(쿠키 등) 격리
- MCP 서버 추가/교체 시 main 이미지 재빌드 불필요

---

## 포트

| 포트 | 용도 |
|---|---|
| `3100` | notebooklm MCP SSE 엔드포인트 (`/sse`, `/message`) |
| `6080` | noVNC 웹 인터페이스 (nlm 재인증 시만 기동) |

---

## 환경변수

| 변수 | 필수 | 기본값 | 설명 |
|---|---|---|---|
| `NOTEBOOKLM_MCP_CLI_PATH` | 권장 | `/mnt/notebooklm/OpenClaw_Auth` | nlm 인증 파일 디렉터리 (gcube 볼륨 마운트 경로) |
| `NLM_MCP_PORT` | 선택 | `3100` | notebooklm MCP SSE 포트 |

---

## main 컨테이너 연결 설정

`openclaw-bot-multi`의 `generate-config.sh`에서 notebooklm MCP를 아래 방식으로 연결:

```json
{
  "mcp": {
    "servers": {
      "notebooklm": {
        "url": "http://localhost:3100/sse"
      }
    }
  }
}
```

---

## NotebookLM 재인증 (nlm-login)

인증 쿠키가 만료됐을 때 컨테이너 내에서 직접 재인증하는 절차.

### 사전 준비

로컬 PC 터미널에서 SSH 터널 연결 (포트 6080 포워딩):

```bash
ssh -p <SSH접속포트> -L 6080:localhost:6080 <사용자아이디>@entry.gcube.ai
```

gcube 포털 → 워크로드 → SSH 접속 정보에서 포트/아이디/비밀번호 확인.

### 재인증 절차

**1. noVNC + nlm login 기동** (컨테이너 터미널에서):

```bash
bash /usr/local/bin/nlm-reauth-start.sh
```

**2. 로컬 브라우저에서 접속**:

```
http://localhost:6080/vnc.html
```

**3. Google 계정으로 로그인**

**4. 완료 후 정리**:

```bash
bash /usr/local/bin/nlm-reauth-finish.sh
```

---

## 파일 구조

```
├── Dockerfile              이미지 빌드 정의
├── entrypoint.sh           NLM 심링크 + supergateway SSE 서버 기동
├── nlm-reauth-start.sh     noVNC + nlm login 기동 (재인증 시)
├── nlm-reauth-finish.sh    인증 파일 저장 + noVNC 정리
└── .github/
    └── workflows/
        └── docker-publish.yml  mcp-hub push 시 ghcr.io 자동 빌드/push
```

---

## 빌드 및 기술 스택

| 항목 | 값 |
|---|---|
| 베이스 이미지 | `ubuntu:22.04` |
| Python 패키지 관리 | `uv` |
| notebooklm-mcp-cli | `uv tool install --python 3.12` |
| stdio → SSE 변환 | `supergateway` (npm) |
| 브라우저 (인증용) | Google Chrome (`.deb` 직접 설치) |
| VNC 스택 | Xvfb + openbox + x11vnc + noVNC |
| Node.js | 24 (JS 기반 MCP 서버 확장 대비) |

---

## 참고 링크

- [notebooklm-mcp-cli GitHub](https://github.com/jacob-bd/notebooklm-mcp-cli)
- [supergateway GitHub](https://github.com/supercorp-ai/supergateway)
- [OpenClaw MCP 설정 레퍼런스](https://docs.openclaw.ai/cli/mcp)
