"""
update_readme.py — README.md 의 OpenClaw 버전 섹션을 자동 업데이트

환경변수:
    OPENCLAW_VERSION : 설치된 openclaw 버전 (예: 2026.3.31)
    BUILD_DATE       : 빌드 날짜 (예: 2026-03-31)
    RELEASE_BODY     : GitHub 릴리즈 노트 본문 (Breaking/Changes 파싱용)
"""

import re
import os

version = os.environ.get("OPENCLAW_VERSION", "-")
build_date = os.environ.get("BUILD_DATE", "-")
release_body = os.environ.get("RELEASE_BODY", "")

def parse_korean_summary(body: str) -> str:
    """Breaking / Changes 섹션에서 항목을 추출해 한국어 개조식으로 변환."""
    lines = body.splitlines()
    breaking = []
    changes = []
    current = None

    for line in lines:
        stripped = line.strip()
        if re.match(r"#+\s*Breaking", stripped):
            current = "breaking"
        elif re.match(r"#+\s*Changes", stripped):
            current = "changes"
        elif re.match(r"#+\s*(Fix|Docs|Chore)", stripped, re.IGNORECASE):
            current = None
        elif stripped.startswith("- ") and current in ("breaking", "changes"):
            # 앞쪽 모듈명/컴포넌트 추출 (예: "Agents/LLM: ..." → "Agents/LLM")
            content = stripped[2:]
            module_match = re.match(r"^([^:]+):\s*(.+)", content)
            if module_match:
                module = module_match.group(1).strip()
                desc = module_match.group(2).strip()
                # 첫 문장만 사용 (마침표 기준)
                first_sentence = re.split(r"\.\s", desc)[0].rstrip(".")
                entry = f"- **{module}**: {first_sentence}"
            else:
                entry = f"- {content.split('.')[0]}"

            if current == "breaking":
                breaking.append(entry)
            else:
                changes.append(entry)

    sections = []
    if breaking:
        sections.append("**주요 변경 (Breaking)**\n\n" + "\n".join(breaking[:5]))
    if changes:
        sections.append("**업데이트 내용**\n\n" + "\n".join(changes[:8]))

    return "\n\n".join(sections) if sections else "- 변경 사항 없음"


summary = parse_korean_summary(release_body) if release_body else "- 릴리즈 노트를 가져올 수 없습니다."

new_section = (
    "<!-- OPENCLAW_VERSION_START -->\n"
    "## OpenClaw 버전 정보\n"
    "\n"
    "> 이미지 빌드 시 자동 갱신됩니다.\n"
    "\n"
    "| 항목 | 내용 |\n"
    "|---|---|\n"
    f"| 설치 버전 | `{version}` |\n"
    f"| 빌드 날짜 | {build_date} |\n"
    "\n"
    "### 주요 변경사항\n"
    "\n"
    f"{summary}\n"
    "<!-- OPENCLAW_VERSION_END -->"
)

with open("README.md", "r") as f:
    content = f.read()

content = re.sub(
    r"<!-- OPENCLAW_VERSION_START -->.*?<!-- OPENCLAW_VERSION_END -->",
    new_section,
    content,
    flags=re.DOTALL,
)

with open("README.md", "w") as f:
    f.write(content)

print(f"README.md updated — openclaw {version} ({build_date})")
