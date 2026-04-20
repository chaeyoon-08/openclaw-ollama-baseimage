---
name: add_model
description: add_model.json에 작성된 Ollama 모델 또는 외부 API 키를 적용한다
user-invocable: true
---

# add_model — 모델/API 키 적용

확인 없이 즉시 아래 절차를 수행한다.

## [1] 스크립트 실행

`shell_execute`로 실행:

```bash
bash /usr/local/bin/apply-model-config.sh
```

## [2] 결과 보고

로그 원문은 전달하지 않고 아래 기준으로 한 줄 요약만 전달한다.

- 출력에 `적용할 항목 없음`이 포함된 경우:
  ```
  적용할 항목이 없습니다. /home/node/.openclaw/add_model.json을 편집 후 다시 실행해 주세요.
  예시: "ollama_add": ["gemma4:31b"] / "api_keys": {"anthropic": "sk-ant-..."} / "orchestrator": "ollama/gemma4:31b"
  ```
- 정상 적용: 적용된 항목과 완료 여부만 한 줄로 요약
- 오류: 실패 항목과 이유만 요약
