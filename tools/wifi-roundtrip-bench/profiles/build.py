#!/usr/bin/env python3
"""Render the four measured executables for a manually deployed Wi-Fi bench profile."""
import argparse
from pathlib import Path

SOURCE = Path(__file__).resolve().parent / "src"
PREFIX = {"ipv4": "blinix-nettrial", "ipv6": "blinix-nettrial-v6"}


def render(text, profile):
    section = "both"
    output = []
    for line in text.splitlines(keepends=True):
        if line.rstrip("\n") in ("@ipv4", "@ipv6", "@both"):
            section = line.rstrip("\n")[1:]
        elif section in ("both", profile):
            output.append(line.replace("@PREFIX@", PREFIX[profile]))
    return "".join(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile", choices=PREFIX)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for source in sorted(SOURCE.glob("*.in")):
        name = source.name.split(".")[0]
        path = args.output / f"{PREFIX[args.profile]}-{name}"
        path.write_text(render(source.read_text(), args.profile))
        path.chmod(0o755)


if __name__ == "__main__":
    main()
