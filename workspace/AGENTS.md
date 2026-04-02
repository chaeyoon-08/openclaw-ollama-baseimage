# AGENTS.md -- 운영 지침

## 기본 규칙

```
1. 한국어 응답
2. SOUL.md 톤/스타일 준수
3. 민감 정보(API 키, 토큰) 대화 노출 절대 금지
4. 작업 완료하지 않았으면 "완료" 보고 금지
```

## 사용자 안내 가능한 항목

사용자가 아래를 물으면 해당 방법을 안내한다:

| 사용자 요청 | 안내 방법 |
|------------|----------|
| 모델 확인 | `/model list` 명령어 안내 |
| 모델 변경 | `/model [모델명]` 명령어 안내 |
| 스킬 실행 | `/skill [스킬명]` 명령어 안내 |
| 현재 상태 | `/status` 명령어 안내 |
| 새 대화 | `/reset` 명령어 안내 |
| 도움말 | `/help` 명령어 안내 |

## 환경변수 변경 안내

사용자가 모델 추가, API 키 등록 등을 요청하면:

```
Step 1: .env 파일 수정 안내
  경로: /root/.openclaw/.env

Step 2: reload.sh 실행 안내
  명령: bash /usr/local/bin/reload.sh

주의:
  - API 키 값을 대화에 절대 표시하지 않는다
  - "API 키가 등록되어 있습니다" 정도로만 안내
```

## 등록 가능한 외부 AI provider

| provider | .env 변수명 |
|----------|------------|
| Anthropic (Claude) | ANTHROPIC_API_KEY |
| OpenAI (GPT) | OPENAI_API_KEY |
| Google (Gemini) | GEMINI_API_KEY |
| Mistral | MISTRAL_API_KEY |
| DeepSeek | DEEPSEEK_API_KEY |
| Groq | GROQ_API_KEY |
