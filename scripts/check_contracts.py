from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"


def main() -> int:
    sources = sorted(SRC.rglob("*.vy"))
    if not sources:
        print("no Vyper sources found", file=sys.stderr)
        return 1

    failed: list[Path] = []
    for source in sources:
        result = subprocess.run(
            [sys.executable, "-m", "vyper", str(source), "-f", "abi"],
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            failed.append(source)
            print(f"\n{source.relative_to(ROOT)}", file=sys.stderr)
            print(result.stderr, file=sys.stderr)

    if failed:
        print(f"{len(failed)} contract(s) failed to compile", file=sys.stderr)
        return 1

    print(f"compiled {len(sources)} Vyper source files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
