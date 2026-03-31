# GCUBE.md — gcube 플랫폼 조사 결과

> 공식 문서 기반으로 확인된 사항과 미확인 사항을 구분하여 정리.
> 출처: https://data-alliance.github.io/gai-platform-docs/

---

## 서비스 개요

- **운영사**: Data Alliance (데이터얼라이언스), 네이버 클라우드 파트너십
- **개요**: GPU 공유경제 플랫폼 — 유휴 GPU 자원을 제공자가 등록하고 소비자가 컨테이너 워크로드로 사용
- **CES 2026 Innovation Award** (AI 부문) 수상
- 공식 사이트: https://gcube.ai

---

## 워크로드 배포

### 지원 이미지 레지스트리 (확인됨)

| 레지스트리 | 주소 |
|---|---|
| Docker Hub | `docker.io` |
| NVIDIA NGC | `nvcr.io` |
| GitHub Container Registry | `ghcr.io` |
| Red Hat Quay | `quay.io` |
| Hugging Face | `registry.hf.space` |

Private 레지스트리는 Storage Management에서 인증 정보 사전 등록 필요.

- 출처: https://data-alliance.github.io/gai-platform-docs/en/user-guide/workload/register-new-workload/

### 이미지 크기 제한
공식 문서에 명시 없음.

### 환경변수 설정
워크로드 등록 시 컨테이너 환경변수 직접 지정 가능 (Dockerfile ENV 오버라이드 포함).

### 최소 CUDA 버전 필드
워크로드 등록 폼에 "최소 CUDA 버전" 지정 항목 있음. 지정한 버전 이상인 노드에 스케줄링됨.
- 노드 요구사항: NVIDIA 드라이버 550+ → CUDA 12.x 호환

---

## 클라우드 저장소 마운트

- **마운트 경로**: `/data/data` (컨테이너 내부 고정 경로)
- **지원 스토리지**: Dropbox, AWS S3 (IAM access key, secret, bucket region 설정)
- Storage Management 메뉴에서 연결 설정 후 워크로드에 연결
- 출처: https://data-alliance.github.io/gai-platform-docs/user-guide/workload/pv-user-guide/

---

## GPU 종류

| Tier | 출처 | 예시 GPU |
|---|---|---|
| Tier 1 (클라우드 CSP) | Naver Cloud 등 | H200, H100 (x1~x8), A100 (40~80GB), V100, T4 |
| Tier 2 (전용 서버) | 데이터센터 | RTX 5090/5080/4090/4080/3090/3080, A6000/A5000/A40 |
| Tier 3 (PC방/개인) | 인터럽트 가능 | RTX 소비자 라인업, Tesla K80, P100 등 |

- 출처: https://gcube.ai/ko/price

---

## 네트워크 정책

| 항목 | 상태 |
|---|---|
| 워크로드별 Service URL 생성 | 확인됨 |
| Istio proxy 사용 | 확인됨 |
| 아웃바운드 HTTP | 가능 (Kubernetes 기본 동작) |
| Telegram long-polling | 동작 예상 (outbound) |
| Telegram webhook 수신 (inbound) | **미확인** — gcube 지원팀 확인 필요 |
| 트래픽 과금 | 인바운드/아웃바운드 ₩30/GB |

→ **Telegram 연동은 long-polling 방식 사용 권장**

---

## 미확인 사항 (gcube 지원팀 확인 필요)

- 외부 inbound 트래픽(Telegram webhook 등) 허용 여부
- 이미지 크기 상한
- Google Drive 마운트 지원 여부 (마케팅 페이지에 언급되나 기술 문서에 없음)
