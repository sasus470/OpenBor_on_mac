"""Measure real embedded-game close latency using the native lifecycle harness."""

import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("harness", type=Path)
    parser.add_argument("pak", type=Path)
    args = parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix="openbor-close-latency-", dir="/tmp"))
    for index in range(3):
        folder = root / str(index)
        env = os.environ.copy()
        env.update(
            EXPECT_CLI_EXIT="1", TEST_REAL_ENGINE="1",
            OPENBOR_FRONTEND_SUPPORT_ROOT=str(folder / "library"),
            OPENBOR_V2_SUPPORT_ROOT=str(folder / "runtime"),
        )
        result = subprocess.run(
            [str(args.harness.resolve()), "--pak", str(args.pak.resolve()),
             "--saves-dir", str(folder / "Saves"), "--logs-dir", str(folder / "Logs")],
            env=env, capture_output=True, text=True, timeout=25, check=True,
        )
        ended = time.time()
        marker = next(line for line in result.stdout.splitlines() if line.startswith("CLOSING_GAME "))
        latency = ended - float(marker.split()[1])
        assert "PASS: CLI game close terminates launcher" in result.stdout
        assert latency < 1.25, f"Close took {latency:.3f}s: {result.stdout}"
        print(f"PASS: real game close {index + 1}: {latency:.3f}s")
    print(f"Test artifacts: {root}")


if __name__ == "__main__":
    main()
