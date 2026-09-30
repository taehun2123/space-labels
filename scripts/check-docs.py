#!/usr/bin/env python3
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parent.parent
documents = [root / "README.md", root / "AGENTS.md", *sorted((root / "docs").glob("*.md"))]
required = {"user-guide.md", "architecture.md", "compatibility.md", "testing.md", "releasing.md"}
errors = []

if {path.name for path in documents} < required | {"README.md", "AGENTS.md"}:
    errors.append("필수 문서가 빠졌습니다.")

for document in documents:
    if not document.is_file():
        errors.append(f"문서를 찾을 수 없습니다: {document}")
        continue
    content = document.read_text(encoding="utf-8")
    targets = re.findall(r"\[[^]]+\]\(([^)]+)\)", content)
    targets += re.findall(r"""<img\b[^>]*\bsrc=["']([^"']+)["']""", content)
    for target in targets:
        if target.startswith(("https://", "http://", "#")):
            continue
        path = (document.parent / target.split("#", 1)[0]).resolve()
        if not path.is_file():
            errors.append(f"깨진 링크: {document.relative_to(root)} → {target}")

index = (root / "AGENTS.md").read_text(encoding="utf-8")
for name in required:
    if name not in index:
        errors.append(f"AGENTS.md 문서 목록에서 빠짐: {name}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"문서 {len(documents)}개: 내부 링크와 문서 목록 확인 완료")
