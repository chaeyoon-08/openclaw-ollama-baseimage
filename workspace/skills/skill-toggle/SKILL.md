---
name: skill-toggle
description: 스킬을 활성화하거나 비활성화 -- SKILL.md frontmatter의 disable-model-invocation 필드를 변경
user-invocable: true
---

# 스킬 on/off

> 트리거: "~꺼줘", "~켜줘", "~비활성화", "~다시 켜줘", "~활성화"

---

## 동작 매핑

| 요청 | SKILL.md frontmatter 변경 | 결과 |
|------|--------------------------|------|
| 끄기 | `disable-model-invocation: true` 추가 | 모델이 이 스킬을 인식하지 않음 |
| 켜기 | `disable-model-invocation` 필드 제거 (또는 false) | 모델이 이 스킬을 정상 인식 |

---

## 플로우

### Step 1: 대상 스킬 확인

```
명확한 경우: 사용자 요청에서 스킬명 추출 → 스킬 폴더 존재 확인
불명확한 경우: skills/ 목록 표시 → 선택 요청
미존재: "해당 스킬이 없습니다."
```

### Step 2: 시스템 스킬 게이트

```
□ 대상이 시스템 스킬인가? (아래 목록에 포함)
  시스템 스킬: onboarding, profile-editor, rule-editor, skill-creator,
              skill-editor, skill-toggle, skill-delete, memory-manager, agent-router, status-dashboard

  → Yes (비활성화 요청):
    "시스템 스킬입니다. 비활성화하면 해당 기능을 대화에서 사용할 수 없습니다."
    "계속할까요?"
    - 승인 → Step 3
    - 거부 → 종료
  → No: Step 3
```

### Step 3: 상태 변경

```
비활성화:
  SKILL.md frontmatter에 disable-model-invocation: true 추가
  (이미 있으면 변경 없음 → "이미 비활성화 상태입니다.")

활성화:
  SKILL.md frontmatter에서 disable-model-invocation 필드 제거
  (이미 없으면 변경 없음 → "이미 활성화 상태입니다.")
```

### Step 4: 완료 알림

```
"[스킬명] [비활성화/활성화] 완료."
"새 세션에서 반영됩니다."
```

---

## 제약

```
MUST:
  - 시스템 스킬 비활성화 시 반드시 경고 + 확인
  - 이미 같은 상태인 경우 안내만 (불필요한 파일 수정 하지 않음)
  - 새 세션 반영 안내

NEVER:
  - 스킬 파일(폴더) 삭제 (frontmatter만 변경)
  - 확인 없이 시스템 스킬 비활성화
```
