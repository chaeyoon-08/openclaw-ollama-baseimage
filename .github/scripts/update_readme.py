"""
update_readme.py — README.md 의 OpenClaw 버전 섹션을 자동 업데이트

환경변수:
    OPENCLAW_VERSION : 설치된 openclaw 버전 (예: 2026.3.31)
    BUILD_DATE       : 빌드 날짜 (예: 2026-03-31)
    RELEASE_BODY     : GitHub 릴리즈 노트 본문
"""

import re
import os

version = os.environ.get("OPENCLAW_VERSION", "-")
build_date = os.environ.get("BUILD_DATE", "-")
release_body = os.environ.get("RELEASE_BODY", "릴리즈 노트를 가져올 수 없습니다.")

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
    "### 릴리즈 노트\n"
    "\n"
    f"{release_body}\n"
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
