---
name: add_model
description: add_model.json에 작성된 Ollama 모델 또는 외부 API 키를 적용한다
user-invocable: true
---

# add_model — 모델/API 키 적용

## 발동 조건

- 사용자가 `/add_model` 입력
- "모델 추가해줘", "API 키 등록해줘" 요청

---

## 절차

### [1] 적용 실행

`shell_execute`로 실행:

```bash
bash /usr/local/bin/apply-model-config.sh
```

### [2] 결과 보고

스크립트 출력을 파싱해 **짧은 요약**만 전달한다. 로그 원문은 전달하지 않는다.

- `적용할 항목 없음` 메시지가 포함된 경우:
  ```
  add_model.json에 적용할 항목이 없습니다.
  파일을 편집 후 /add_model을 다시 실행해 주세요.

  작성 예시:
    Ollama 모델 추가       →  "ollama_add": ["gemma4:31b"]
    API 키 추가            →  "api_keys": {"anthropic": "sk-ant-..."}
    오케스트레이터 교체    →  "orchestrator": "ollama/gemma4:31b"
  ```

- 정상 적용된 경우: 적용된 항목 목록과 완료 여부만 한 줄씩 정리해 전달한다.
  예) "gemma4:31b 다운로드 완료 및 워커 모델 등록, anthropic API 키 등록됨."

- 오류가 발생한 경우: 실패한 항목과 이유만 요약해 전달한다.
