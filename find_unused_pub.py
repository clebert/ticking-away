#!/usr/bin/env python3
"""Find potentially unused pub declarations in Zig code.

Usage: python3 find_unused_pub.py
"""

import re
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent


def get_all_zig_files():
    """Get all .zig files in the project."""
    return list(PROJECT_ROOT.rglob("*.zig"))


def get_lib_zig_files():
    """Get .zig files in lib/zig only."""
    return list((PROJECT_ROOT / "lib" / "zig").rglob("*.zig"))


def extract_pub_declarations(filepath):
    """Extract all pub declarations from a file."""
    declarations = []
    with open(filepath, "r") as f:
        lines = f.read().split("\n")

    patterns = [
        (r"^\s*pub\s+fn\s+(\w+)\s*\(", "fn"),
        (r"^\s*pub\s+const\s+(\w+)\s*=\s*(?!@import)", "const"),
        (r"^\s*pub\s+var\s+(\w+)\s*[:=]", "var"),
    ]

    for line_num, line in enumerate(lines, 1):
        for pattern, decl_type in patterns:
            match = re.match(pattern, line)
            if match:
                name = match.group(1)
                if name.startswith("_") or name in ["std", "Self"]:
                    continue
                declarations.append(
                    {
                        "name": name,
                        "type": decl_type,
                        "line": line_num,
                        "file": str(filepath.relative_to(PROJECT_ROOT)),
                    }
                )
                break

    return declarations


def get_all_content(files):
    """Get combined content of all files."""
    combined = []
    for f in files:
        with open(f, "r") as fp:
            combined.append((str(f.relative_to(PROJECT_ROOT)), fp.read()))
    return combined


def count_references(name, all_content, exclude_file, exclude_line):
    """Count non-declaration references to a name."""
    count = 0
    locations = []

    for filepath, content in all_content:
        lines = content.split("\n")
        for line_num, line in enumerate(lines, 1):
            if filepath == exclude_file and line_num == exclude_line:
                continue

            pattern = rf"(?<![a-zA-Z_])({re.escape(name)})(?![a-zA-Z0-9_])"
            if re.search(pattern, line):
                count += 1
                if len(locations) < 3:
                    locations.append(f"{filepath}:{line_num}")

    return count, locations


def main():
    lib_files = get_lib_zig_files()
    all_files = get_all_zig_files()

    print(f"Analyzing {len(lib_files)} lib/zig files...")
    print(f"Searching for usages across {len(all_files)} total Zig files...\n")

    all_content = get_all_content(all_files)

    all_declarations = []
    for filepath in lib_files:
        if filepath.name == "root.zig":
            continue
        decls = extract_pub_declarations(filepath)
        all_declarations.extend(decls)

    print(f"Found {len(all_declarations)} pub declarations in lib/zig\n")

    unused = []
    internal_only = []

    for decl in all_declarations:
        name = decl["name"]
        ref_count, locations = count_references(
            name, all_content, decl["file"], decl["line"]
        )

        if ref_count == 0:
            unused.append(decl)
        elif ref_count == 1:
            if locations and decl["file"] in locations[0]:
                decl["note"] = f"Only used internally at {locations[0]}"
                internal_only.append(decl)

    if unused:
        print("UNUSED pub declarations (no references found):")
        print("=" * 70)
        for decl in sorted(unused, key=lambda x: (x["file"], x["line"])):
            print(f"{decl['file']}:{decl['line']}: pub {decl['type']} {decl['name']}")
        print(f"\nTotal: {len(unused)} unused pub declarations")
    else:
        print("No completely unused pub declarations found.")

    if internal_only:
        print("\n\nPub declarations only used once internally (may not need pub):")
        print("=" * 70)
        for decl in sorted(internal_only, key=lambda x: (x["file"], x["line"])):
            print(f"{decl['file']}:{decl['line']}: pub {decl['type']} {decl['name']}")
            if "note" in decl:
                print(f"    {decl['note']}")


if __name__ == "__main__":
    main()
