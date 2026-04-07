# PVE / 독립 Docker 호스트 배포 가이드

> **이 문서와 `docker-compose.yml`은 현재 기획 단계의 초안입니다.**
> 실제 환경에서의 테스트가 완료되지 않았으며, 향후 수정이 있을 수 있습니다. 참고 용도로만 활용하세요.

gcube 웹 UI 없이 Proxmox VE 또는 독립 Docker 호스트에서 직접 배포할 때 사용합니다.

---

## 사전 요건

- Docker Engine 설치
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) 설치
- NVIDIA 드라이버 570.124.06 이상

---

## 배포 방법

### 1. `docker-compose.yml` 준비

아래 중 편한 방법을 선택합니다.

**방법 A — 파일 내용 복붙**

`docker-compose.yml`의 내용을 복사하여 원하는 경로에 파일을 생성합니다.

**방법 B — curl로 다운로드**

```bash
curl -fsSL https://raw.githubusercontent.com/chaeyoon-08/openclaw-ollama-baseimage/main/pve/docker-compose.yml \
  -o docker-compose.yml
```

---

### 2. `.env` 파일 생성

`docker-compose.yml`과 같은 디렉터리에 `.env` 파일을 생성합니다.

```env
# 필수
TELEGRAM_BOT_TOKEN=1234567890:AAF...
TELEGRAM_ALLOWED_USER_IDS=123456789
OLLAMA_MODEL=qwen3.5:9b
OPENCLAW_GATEWAY_TOKEN=my-token-1234

# 선택 — 외부 AI provider
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
GEMINI_API_KEY=
MISTRAL_API_KEY=
DEEPSEEK_API_KEY=
GROQ_API_KEY=

# 선택 — GitHub 연동
GITHUB_USERNAME=
GITHUB_EMAIL=
GITHUB_TOKEN=
GITHUB_REPO_URL=
```

---

### 3. 컨테이너 실행

```bash
docker compose up -d
```

### 4. 로그 확인

```bash
docker logs -f openclaw-bot
```

아래 메시지가 출력되면 정상입니다.

```
[ DONE  ] All services started
[telegram] [default] starting provider (@your_bot_name)
```

---

## 포트

| 포트 | 용도 |
|---|---|
| `18789` | OpenClaw Gateway / Control UI |

Control UI 접근: `http://<호스트-IP>:18789`

---

## 볼륨

| 볼륨 | 경로 | 설명 |
|---|---|---|
| `ollama-models` | `/root/.ollama` | Ollama 모델 캐시. 재시작 시 재다운로드 방지 |
| (선택) `./workspace` | `/workspace` | 작업 파일 영구 보존. `docker-compose.yml`에서 주석 해제 |

---

## GPU 설정

`docker-compose.yml`의 `count` 값으로 사용할 GPU 수를 지정합니다.

```yaml
devices:
  - driver: nvidia
    count: 1      # GPU 1개 사용. 전체 할당 시 "all"
    capabilities: [gpu]
```

---

## 참고

| 문서 | URL |
|---|---|
| NVIDIA Container Toolkit | https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html |
| Ollama 모델 라이브러리 | https://ollama.com/library |
| 컨테이너 이미지 | `ghcr.io/chaeyoon-08/openclaw-bot:latest` |
