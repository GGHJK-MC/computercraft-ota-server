#!/usr/bin/env python3
"""Generate the content manifest consumed by installer.lua.

Examples:
    python3 generate_content.py
    python3 generate_content.py --branch develop-1.0
"""

import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path
from urllib.parse import quote


DEFAULT_EXCLUDES = (
    "content.json",
    "main.py",
    ".git/*",
    "__pycache__/*",
    "installer.lua",
    "README.md",
    "LICENSE",

)
DEFAULT_CDN_PREFIX = "https://cdn.gghjk.qzz.io/cct/os/"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(64 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def djb2(path: Path) -> str:
    value = 5381
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(64 * 1024), b""):
            for byte in chunk:
                value = ((value << 5) + value + byte) & 0xFFFFFFFF
    return f"{value:08x}"


def is_excluded(relative_path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatchcase(relative_path, pattern) for pattern in patterns)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create content.json with each file's relative path, hashes, and download URL."
    )
    parser.add_argument(
        "--base-url",
        help="Override the public base URL where files will be hosted.",
    )
    parser.add_argument(
        "--branch",
        default="latest-stable",
        choices=("latest-stable", "master-1.0", "develop-1.0", "latest", "master-2.0", "develop-2.0"),
        help="Installer branch used to build the default CDN URL (default: latest-stable).",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent,
        help="Directory to scan (default: directory containing this script).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Output manifest path (default: <root>/content.json).",
    )
    parser.add_argument(
        "--exclude",
        action="append",
        default=[],
        metavar="PATTERN",
        help="Additional relative path glob to exclude; can be repeated.",
    )
    args = parser.parse_args()

    root = args.root.resolve()
    if not root.is_dir():
        parser.error(f"root directory does not exist: {root}")

    output = args.output or root / "content.json"
    output = output.resolve()
    base_url = args.base_url or DEFAULT_CDN_PREFIX + args.branch + "/"
    base_url = base_url.rstrip("/") + "/"
    excludes = list(DEFAULT_EXCLUDES) + args.exclude
    try:
        excludes.append(output.relative_to(root).as_posix())
    except ValueError:
        pass

    manifest = []
    for current_dir, directories, filenames in os.walk(root):
        directories[:] = sorted(
            directory for directory in directories
            if directory not in (".git", "__pycache__")
        )
        for filename in sorted(filenames):
            path = Path(current_dir) / filename
            relative_path = path.relative_to(root).as_posix()
            if is_excluded(relative_path, excludes):
                continue

            manifest.append({
                "path": relative_path,
                "sha256": sha256(path),
                "djb2": djb2(path),
                "url": base_url + quote(relative_path, safe="/"),
            })

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary_output = output.with_name(output.name + ".tmp")
    temporary_output.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    temporary_output.replace(output)
    print(f"Generated {output} with {len(manifest)} files.")


if __name__ == "__main__":
    main()
