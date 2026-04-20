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

실행 결과를 그대로 사용자에게 전달한다.

적용할 항목이 없다는 메시지가 나오면:

```
add_model.json에 적용할 항목이 없습니다.
/home/node/.openclaw/add_model.json 파일을 편집 후 /add_model을 다시 실행해 주세요.

작성 예시:
  Ollama 모델 추가  →  "ollama_add": ["gemma4:31b"]
  API 키 추가       →  "api_keys": {"anthropic": "sk-ant-..."}
```
