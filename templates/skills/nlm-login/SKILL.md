# 스킬: nlm-login — NotebookLM 재인증

## 상태

> **미구현 (껍데기)** — 이 스킬은 아직 이 파일로 이전되지 않았습니다.
> 현재 nlm-login 절차는 `TOOLS.md`의 "스킬: nlm-login" 섹션을 참조하십시오.

---

## 구현 예정 내용

- [1단계] noVNC + nlm login 프로세스 시작 (`nlm-reauth-start.sh`)
- [2단계] 사용자에게 SSH 터널 + 브라우저 접속 안내
- [3단계] 사용자 완료 확인 후 인증 파일 저장 (`nlm-reauth-finish.sh`)
- [4단계] gateway reload (`reload.sh`)
- [5단계] 완료 안내 및 NLM 도구 재시도

---

## 현재 참조 위치

```
workspace/TOOLS.md — "스킬: nlm-login" 섹션
```
