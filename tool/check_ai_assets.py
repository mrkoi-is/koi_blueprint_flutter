#!/usr/bin/env python3
"""Validate local AI discovery, canonical instructions and source references.

Uses only Python's standard library. The skills index intentionally accepts the
repository's small flat YAML schema, not arbitrary YAML. No files are modified.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit


CLAUDE_ADAPTER = """# Flutter workspace agent entry

@AGENTS.md

Read `AGENTS.md`, `docs/ai-quickstart.md` and `.agent/skills/index.yaml`.
This file only routes discovery; update the canonical files for architecture and task guidance.
"""

CURSOR_ADAPTER = """---
description: Flutter workspace task routing
alwaysApply: true
---

Read `AGENTS.md`, then `docs/ai-quickstart.md` and `.agent/skills/index.yaml`.
Load only the canonical skill for the current task and the references it needs.
Project rules live in `AGENTS.md` and the linked architecture documents; this file only routes discovery.
"""


@dataclass(frozen=True)
class Issue:
    rule: str
    path: str
    message: str


def frontmatter(text: str) -> tuple[str, dict[str, str]]:
    match = re.match(r"\A---\n(.*?)\n---(?:\n|$)", text, re.S)
    if not match:
        raise ValueError("Missing YAML frontmatter")
    values = {}
    for line in match[1].splitlines():
        pair = re.fullmatch(r"([a-z_]+):\s*(.+)", line)
        if not pair or pair[1] in values:
            raise ValueError("Frontmatter must contain unique scalar fields")
        values[pair[1]] = pair[2].strip().strip('"\'')
    if not values.get("name") or not values.get("description"):
        raise ValueError("Frontmatter requires name and description")
    return match[0].rstrip("\n"), values


def expected_adapter(canonical: str, skill_id: str) -> str:
    header, _ = frontmatter(canonical)
    return (f"{header}\n\nRead the canonical skill at `.agent/skills/{skill_id}/SKILL.md` "
            "from the repository root and follow it.\n"
            "This file is a discovery adapter; edit only the canonical skill.\n")


def read_index(path: Path) -> list[dict[str, object]]:
    """Parse the constrained index schema and fail on unsupported YAML features."""
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "skills:":
        raise ValueError("Index must begin with skills:")
    entries: list[dict[str, object]] = []
    for line in lines[1:]:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        first = re.fullmatch(r"  - id: ([a-z][a-z0-9-]*)", line)
        if first:
            entries.append({"id": first[1]})
            continue
        field = re.fullmatch(r"    (description|keywords|path): (.+)", line)
        if not field or not entries or field[1] in entries[-1]:
            raise ValueError(f"Unsupported or duplicate index field: {line}")
        key, value = field.groups()
        if key == "keywords":
            if not re.fullmatch(r"\[[a-zA-Z0-9_ -]+(?:,\s*[a-zA-Z0-9_ -]+)*\]", value):
                raise ValueError("keywords must be a nonempty inline list of simple words")
            entries[-1][key] = [item.strip() for item in value[1:-1].split(",")]
        else:
            entries[-1][key] = value.strip('"\'')
    if not entries:
        raise ValueError("Index must contain at least one skill")
    for entry in entries:
        if set(entry) != {"id", "description", "keywords", "path"}:
            raise ValueError(f"Incomplete skill index entry: {entry.get('id')}")
    return entries


def _without_fences(text: str) -> str:
    kept = []
    fence: tuple[str, int] | None = None
    for line in text.splitlines(keepends=True):
        content = line.rstrip("\r\n")
        opening = re.match(r"^[ \t]*(`{3,}|~{3,})", content)
        if fence is None:
            if opening:
                marker = opening[1]
                fence = (marker[0], len(marker))
            else:
                kept.append(line)
        elif re.fullmatch(r"[ \t]*" + re.escape(fence[0]) + "{" + str(fence[1]) + r",}[ \t]*", content):
            fence = None
    return "".join(kept)


def _concrete(path: str) -> bool:
    return not any(marker in path for marker in ("<", ">", "*", "{", "}", "|", "\n"))


def _reference_target(root: Path, document: Path, target: str) -> Path | None:
    parts = urlsplit(target)
    if parts.scheme or parts.netloc or not parts.path:
        return None
    value = unquote(parts.path)
    if not _concrete(value):
        return None
    candidate = (document.parent / value).resolve()
    if candidate.exists():
        return candidate
    # Backtick repository paths and explicitly root-based documentation paths.
    root_candidate = (root / value).resolve()
    return root_candidate if root_candidate.exists() else candidate


def check_references(root: Path, documents: list[Path]) -> list[Issue]:
    issues = []
    root_prefixes = ("apps/", "examples/", "packages/", "modules/", "tool/", "scripts/",
                     "docs/", ".agent/", ".agents/", ".cursor/", ".blueprint/")
    root_files = {"AGENTS.md", "CLAUDE.md", "README.md", "pubspec.yaml", ".fvmrc", "blueprint.py"}
    for document in documents:
        text = _without_fences(document.read_text(encoding="utf-8"))
        path = document.relative_to(root).as_posix()
        targets = []
        for match in re.finditer(r"(?<!!)\[[^\]\n]+\]\((<[^>]+>|[^)\n]+)\)", text):
            value = match[1]
            if value.startswith("<"):
                value = value[1:-1]
            else:
                value = re.split(r'\s+["\']', value, maxsplit=1)[0]
            targets.append(value)
        for match in re.finditer(r"(?<!`)`([^`\n]+)`(?!`)", text):
            value = match[1]
            if value in root_files or value.startswith(root_prefixes) or value.startswith("references/"):
                if value.rstrip("/") in {p.rstrip("/") for p in root_prefixes}:
                    continue  # Layout headings name optional top-level folders.
                if value == ".blueprint/reference/" and not (root / value).exists():
                    continue  # Documented output location in the source blueprint.
                if " " not in value and _concrete(value):
                    targets.append(value)
        for target in sorted(set(targets)):
            if target.startswith(("/Users/", "/home/")) or re.match(r"[A-Za-z]:[\\/]Users[\\/]", target):
                issues.append(Issue("AI_PORTABLE", path, f"Machine-specific reference: {target}"))
                continue
            resolved = _reference_target(root, document, target)
            if resolved is None:
                continue
            if not resolved.is_relative_to(root):
                issues.append(Issue("AI_REFERENCE", path, f"Reference escapes repository: {target}"))
            elif not resolved.exists():
                issues.append(Issue("AI_REFERENCE", path, f"Missing local reference: {target}"))
    return issues


def validate_assets(root: Path) -> list[Issue]:
    root = root.resolve()
    issues: list[Issue] = []
    index_path = root / ".agent/skills/index.yaml"
    try:
        entries = read_index(index_path)
    except (OSError, ValueError) as error:
        return [Issue("AI_INDEX", ".agent/skills/index.yaml", str(error))]
    ids = [str(entry["id"]) for entry in entries]
    if len(ids) != len(set(ids)):
        issues.append(Issue("AI_INDEX", ".agent/skills/index.yaml", "Duplicate skill ids"))
    canonical_ids = {p.parent.name for p in (root / ".agent/skills").glob("*/SKILL.md")}
    adapter_ids = {p.parent.name for p in (root / ".agents/skills").glob("*/SKILL.md")}
    for label, found in (("canonical", canonical_ids), ("adapter", adapter_ids)):
        if found != set(ids):
            issues.append(Issue("AI_INDEX", ".agent/skills/index.yaml",
                                f"{label} discovery differs from index: missing={sorted(set(ids)-found)}, extra={sorted(found-set(ids))}"))
    for entry in entries:
        skill_id = str(entry["id"])
        expected_path = f".agent/skills/{skill_id}/SKILL.md"
        if entry["path"] != expected_path:
            issues.append(Issue("AI_INDEX", ".agent/skills/index.yaml", f"Noncanonical path for {skill_id}"))
        canonical_path = root / expected_path
        adapter_path = root / f".agents/skills/{skill_id}/SKILL.md"
        try:
            canonical = canonical_path.read_text(encoding="utf-8")
            _, metadata = frontmatter(canonical)
            if metadata["name"] != skill_id or metadata["description"] != entry["description"]:
                issues.append(Issue("AI_METADATA", expected_path, "Canonical metadata differs from index"))
            if canonical_path.is_symlink() or adapter_path.is_symlink():
                issues.append(Issue("AI_ADAPTER", adapter_path.relative_to(root).as_posix(),
                                    "Use real discovery files for consistent Windows checkouts"))
            if adapter_path.read_text(encoding="utf-8") != expected_adapter(canonical, skill_id):
                issues.append(Issue("AI_ADAPTER", adapter_path.relative_to(root).as_posix(),
                                    "Discovery adapter differs from the canonical metadata/routing template"))
        except (OSError, ValueError) as error:
            issues.append(Issue("AI_METADATA", expected_path, str(error)))
    routes = {
        "AGENTS.md": ("docs/ai-quickstart.md", ".agent/skills/index.yaml"),
        "docs/ai-quickstart.md": ("AGENTS.md", ".agent/skills/index.yaml"),
    }
    for name, required in routes.items():
        path = root / name
        text = path.read_text(encoding="utf-8") if path.is_file() else ""
        for value in required:
            if value not in text:
                issues.append(Issue("AI_ROUTING", name, f"Missing canonical entry reference: {value}"))
    for name, expected in (("CLAUDE.md", CLAUDE_ADAPTER),
                           (".cursor/rules/koi-workspace.mdc", CURSOR_ADAPTER)):
        path = root / name
        if not path.is_file() or path.read_text(encoding="utf-8") != expected:
            issues.append(Issue("AI_ROUTING", name, "Discovery entry differs from the canonical adapter template"))
    agent_path = root / "AGENTS.md"
    if agent_path.is_file():
        agent_text = agent_path.read_text(encoding="utf-8")
        match = re.search(r"(?m)^## 任务路由\s*\n(.*?)(?=^## |\Z)", agent_text, re.S | re.M)
        if match:
            route_ids = re.findall(r"(?m)^\|[^|\n]+\|\s*`([a-z][a-z0-9-]*)`\s*\|\s*$", match[1])
            if len(route_ids) != len(set(route_ids)) or set(route_ids) != set(ids):
                issues.append(Issue("AI_ROUTING", "AGENTS.md", "Task routing skill IDs differ from the canonical index"))
    # Research notes and dated validation evidence are not current AI routing
    # documents; they may legitimately cite source machines or planned paths.
    source_only_docs = {("docs", "research"), ("docs", "validation")}
    documents = [p for base in (root / ".agent/skills", root / ".agents/skills", root / "docs")
                 if base.is_dir() for p in base.rglob("*.md")
                 if tuple(p.relative_to(root).parts[:2]) not in source_only_docs]
    documents.extend(root / name for name in ("AGENTS.md", "CLAUDE.md", "README.md", "DESIGN.md") if (root / name).is_file())
    cursor = root / ".cursor/rules/koi-workspace.mdc"
    if cursor.is_file():
        documents.append(cursor)
    issues.extend(check_references(root, documents))
    # Sample maps point to executable source and tests; snapshots in generated
    # projects stay outside the workspace but retain their source/test pairs.
    source = root / ".blueprint/reference" if (root / ".blueprint/reference").is_dir() else root
    if (root / "blueprint.py").is_file():
        for name in ("starter_app", "feature_lab", "minimal_module", "workbench_app", "ui_lab"):
            sample = source / "examples" / name
            for item in ("pubspec.yaml", "lib", "test"):
                if not (sample / item).exists():
                    issues.append(Issue("AI_TEMPLATE", "blueprint.py", f"Missing executable source/test input: {sample.relative_to(root).as_posix()}/{item}"))
        for feature in ("welcome", "catalog", "draft"):
            for folder in ("lib", "test"):
                if not (source / f"examples/feature_lab/{folder}/features/{feature}").is_dir():
                    issues.append(Issue("AI_TEMPLATE", "blueprint.py", f"Missing feature template {folder}: {feature}"))
    placeholder = re.compile(r"\{\{\s*(?:app|project|feature|module|org)_name\s*\}\}|__(?:APP|PROJECT|FEATURE|MODULE|ORG)_NAME__")
    for folder in ("apps", "packages", "modules", "examples"):
        base = root / folder
        if not base.is_dir():
            continue
        for file in base.rglob("*.dart"):
            if "lib" not in file.parts or any(part in {"build", ".dart_tool"} for part in file.parts):
                continue
            if file.name.endswith((".g.dart", ".freezed.dart")):
                continue
            if placeholder.search(file.read_text(encoding="utf-8")):
                issues.append(Issue("AI_TEMPLATE", file.relative_to(root).as_posix(), "Unexpanded generation placeholder in executable source"))
    return sorted(set(issues), key=lambda issue: (issue.path, issue.rule, issue.message))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        issues = validate_assets(args.root)
    except (OSError, ValueError) as error:
        print(f"AI asset checker failed: {error}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps({"ok": not issues, "issues": [asdict(issue) for issue in issues]}, ensure_ascii=False))
    elif issues:
        for issue in issues:
            print(f"{issue.path} [{issue.rule}] {issue.message}", file=sys.stderr)
    else:
        print("AI asset checks passed (canonical skills, discovery adapters, references and template inputs).")
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
