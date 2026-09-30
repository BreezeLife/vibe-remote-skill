#!/usr/bin/env python3
"""Install this repository's skill by symlink; never replace unrelated content."""
import argparse
import os
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path,
                        help="Skills directory; defaults to CODEX_HOME/skills or ~/.codex/skills")
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1] / "skills" / "vibe-remote"
    if not (source / "SKILL.md").is_file():
        parser.error("Source skill is missing")
    codex_dir = Path(os.environ.get("CODEX_HOME") or (Path.home() / ".codex"))
    destination = args.destination or (codex_dir / "skills")
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / "vibe-remote"
    if target.is_symlink() and target.resolve() == source.resolve():
        print(f"Already installed: {target}")
        return
    if target.exists() or target.is_symlink():
        parser.error(f"Refusing to overwrite existing content: {target}")
    target.symlink_to(source, target_is_directory=True)
    print(f"Installed: {target} -> {source}")


if __name__ == "__main__":
    main()
