#!/usr/bin/env python3
"""Collect prompt-like files from a source tree into a golden-prompts folder."""

from __future__ import annotations

import argparse
import hashlib
import os
from datetime import datetime, timezone
from pathlib import Path


PRUNE_DIRS = {
    ".git",
    "node_modules",
    "build",
    "dist",
    "obj",
    ".dart_tool",
    ".venv",
    "venv",
    "__pycache__",
    "golden-prompts",
}

TEXT_SUFFIXES = {
    ".md",
    ".txt",
    ".json",
    ".py",
    ".mjs",
    ".js",
    ".ts",
    ".tsx",
    ".vue",
    ".cs",
}

CODE_SUFFIXES = {".py", ".mjs", ".js", ".ts", ".tsx", ".vue", ".cs"}

EXCLUDE_NAME_PARTS = {
    "package-lock.json",
    "pnpm-lock.yaml",
    "auto-imports.d.ts",
    "components.d.ts",
}


def is_candidate(path: Path, source_root: Path) -> bool:
    rel_parts = path.relative_to(source_root).parts
    if any(part in PRUNE_DIRS for part in rel_parts):
        return False
    if path.name in EXCLUDE_NAME_PARTS:
        return False
    if path.suffix.lower() not in TEXT_SUFFIXES:
        return False

    lower_name = path.name.lower()
    lower_rel = "/".join(part.lower() for part in rel_parts)

    if lower_name == "skill.md":
        return True
    if "prompt" in lower_name:
        return True
    if "/prompts/" in lower_rel or "/prompt_presets/" in lower_rel:
        return True
    if "/agents/" in lower_rel and path.suffix.lower() == ".md":
        return True
    if "/skills/" in lower_rel and (
        lower_name == "skill.md"
        or "/references/" in lower_rel
        or "/templates/" in lower_rel
    ):
        return True
    if "/.harness/agents/" in lower_rel or "/.harness/skills/" in lower_rel:
        return True
    if "/genres/" in lower_rel and path.suffix.lower() == ".md":
        return True
    if "/templates/" in lower_rel and path.suffix.lower() == ".md":
        return True
    if "/protocols/" in lower_rel and path.suffix.lower() == ".md":
        return True
    if "/aesthetic/" in lower_rel and path.suffix.lower() == ".md":
        return True
    if "/codex/" in lower_rel and path.suffix.lower() == ".md":
        return True
    if "/core/" in lower_rel and path.suffix.lower() == ".md":
        return True
    return False


def classify(path: Path, source_root: Path) -> str:
    lower = "/".join(part.lower() for part in path.relative_to(source_root).parts)
    name = path.name.lower()
    if name == "skill.md" or "/skills/" in lower or "/.harness/skills/" in lower:
        return "skill"
    if "/agents/" in lower or "/.harness/agents/" in lower:
        return "agent"
    if "/prompt_presets/" in lower:
        return "prompt-preset"
    if "/prompts/" in lower or "prompt" in name:
        return "prompt"
    if "/genres/" in lower:
        return "genre-reference"
    if "/templates/" in lower:
        return "template"
    if "/protocols/" in lower:
        return "protocol"
    if "/aesthetic/" in lower or "/codex/" in lower or "/core/" in lower:
        return "system-reference"
    return "reference"


def project_name(path: Path, source_root: Path) -> str:
    rel = path.relative_to(source_root)
    return rel.parts[0] if rel.parts else "_root"


def safe_rel(path: Path, source_root: Path) -> Path:
    rel = path.relative_to(source_root)
    parts = []
    for part in rel.parts:
        cleaned = part.replace(":", "_").replace("\\", "_")
        parts.append(cleaned)
    return Path(*parts)


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="utf-8", errors="replace")


def wrap_content(source: Path, content: str, collected_at: str, source_root: Path) -> str:
    rel = source.relative_to(source_root)
    digest = hashlib.sha256(content.encode("utf-8", errors="replace")).hexdigest()
    header = [
        "---",
        f"source: {source}",
        f"source_relative: {rel}",
        f"source_project: {project_name(source, source_root)}",
        f"source_kind: {classify(source, source_root)}",
        f"source_sha256: {digest}",
        f"collected_at: {collected_at}",
        "---",
        "",
        f"<!-- Source: {source} -->",
        "",
    ]
    return "\n".join(header) + content


def write_index(
    records: list[dict[str, str]],
    collected_at: str,
    source_root: Path,
    dest_root: Path,
) -> None:
    by_kind: dict[str, int] = {}
    by_project: dict[str, int] = {}
    for record in records:
        by_kind[record["kind"]] = by_kind.get(record["kind"], 0) + 1
        by_project[record["project"]] = by_project.get(record["project"], 0) + 1

    lines = [
        "# Golden Prompts Index",
        "",
        f"Collected at: `{collected_at}`",
        f"Source root: `{source_root}`",
        f"Files collected: `{len(records)}`",
        "",
        "## By Kind",
        "",
    ]
    for kind, count in sorted(by_kind.items()):
        lines.append(f"- `{kind}`: {count}")

    lines.extend(["", "## By Project", ""])
    for project, count in sorted(by_project.items()):
        lines.append(f"- `{project}`: {count}")

    lines.extend(["", "## Files", ""])
    for record in records:
        lines.append(
            "- "
            f"`{record['kind']}` "
            f"`{record['project']}` "
            f"[{record['dest']}]({record['dest']}) "
            f"← `{record['source']}`"
        )

    (dest_root / "INDEX.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_recommendations(
    records: list[dict[str, str]],
    collected_at: str,
    dest_root: Path,
) -> None:
    lines = [
        "# Import Recommendations",
        "",
        f"Generated at: `{collected_at}`",
        "",
        "## Recommended For Reveric Official AgentSkill Catalog",
        "",
        "- `oh-story-claudecode/skills/story-long-write/SKILL.md`: strong long-form workflow, but should be distilled before import because it assumes Claude plugin files and external agents.",
        "- `character-arc/resources/skills/Distilled-Novel-Toolbox/novel-pacing/SKILL.md`: clear chapter/opening/pacing rules; overlaps with the existing official 章节节奏 skill, best imported as focused additions.",
        "- `character-arc/resources/skills/Distilled-Novel-Toolbox/novel-worldbuilding/SKILL.md`: useful worldbuilding and rule-consistency framework; low coupling.",
        "- `character-arc/resources/skills/Distilled-Novel-Toolbox/novel-character-design/SKILL.md`: useful for strengthening `character_analyst` and future character design agents.",
        "- `novel-harness/.harness/agents/写作Agent.md`: useful role boundaries for writer agents; import as constraints, not as a full agent prompt.",
        "- `tianming-skill/SKILL.md` plus `tianming-skill/protocols/*.md`: valuable protocol design, but too command-system-specific for direct import.",
        "- `BiXian-AI-Novel/bixian/prompts/md/blocks/*.md`: strong prompt blocks for webnovel voice, anti-AI flavor, chapter design, and compliance; import selectively into official AgentSkills.",
        "",
        "## Not Recommended For Direct Import",
        "",
        "- UI files, prompt management services, migrations, and tests: useful for implementation ideas, not prompt assets.",
        "- Full prompt preset trees from `inliver233_ai_novel`: high value, but they assume that app's prompt-block renderer and memory model.",
        "- Large genre/template libraries: better handled as future searchable reference packs than official AgentSkills.",
        "- Platform policy/compliance material: may be outdated and should not be treated as current legal/platform guidance without verification.",
        "",
        "## Reveric Import Strategy",
        "",
        "1. Keep `golden-prompts` as the raw evidence library with source references.",
        "2. Publish only distilled, stable writing rules as versioned official AgentSkills.",
        "3. Avoid adding prompt files to `assets/prompts` unless a Dart call site and `PromptRegistry` ID are defined.",
        "4. Reuse writing guidance by installing official AgentSkills for the novel and loading them through AgentSkill.",
        "",
        "## Candidate Counts",
        "",
    ]

    counts: dict[str, int] = {}
    for record in records:
        key = f"{record['project']} / {record['kind']}"
        counts[key] = counts.get(key, 0) + 1
    for key, count in sorted(counts.items()):
        lines.append(f"- `{key}`: {count}")

    (dest_root / "IMPORT_RECOMMENDATIONS.md").write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Collect prompt-like files from SOURCE_ROOT into an output "
            "golden-prompts folder."
        ),
    )
    parser.add_argument(
        "source_root",
        type=Path,
        help="Root directory to scan.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Destination directory. Defaults to SOURCE_ROOT/golden-prompts.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    source_root = args.source_root.expanduser().resolve()
    dest_root = (
        args.output_dir.expanduser().resolve()
        if args.output_dir is not None
        else source_root / "golden-prompts"
    )
    if not source_root.is_dir():
        raise SystemExit(f"source_root is not a directory: {source_root}")

    collected_at = datetime.now(timezone.utc).isoformat()
    dest_root.mkdir(parents=True, exist_ok=True)

    records: list[dict[str, str]] = []
    for root, dirs, files in os.walk(source_root):
        dirs[:] = [d for d in dirs if d not in PRUNE_DIRS]
        root_path = Path(root)
        for filename in sorted(files):
            source = root_path / filename
            if not is_candidate(source, source_root):
                continue
            content = read_text(source)
            rel = safe_rel(source, source_root)
            dest_rel = Path("sources") / rel
            if source.suffix.lower() in CODE_SUFFIXES:
                dest_rel = dest_rel.with_suffix(source.suffix + ".md")
            dest = dest_root / dest_rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(
                wrap_content(source, content, collected_at, source_root),
                encoding="utf-8",
            )
            records.append(
                {
                    "source": str(source.relative_to(source_root)),
                    "dest": str(dest.relative_to(dest_root)),
                    "project": project_name(source, source_root),
                    "kind": classify(source, source_root),
                }
            )

    records.sort(key=lambda item: (item["project"], item["kind"], item["source"]))
    write_index(records, collected_at, source_root, dest_root)
    write_recommendations(records, collected_at, dest_root)
    print(f"Collected {len(records)} files into {dest_root}")


if __name__ == "__main__":
    main()
