"""CLI smoke test using an isolated support root and a user-supplied PAK."""

import argparse
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time


def stop_test_processes(host, frame):
    # Foundation launches the engine in its own process group.
    result = subprocess.run(
        ["lsof", "-t", str(frame)], capture_output=True, text=True, check=False
    )
    engine_pids = {int(pid) for pid in result.stdout.split()} - {host.pid}
    for pid in engine_pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    try:
        os.killpg(host.pid, signal.SIGTERM)
        host.wait(timeout=3)
    except ProcessLookupError:
        pass
    except subprocess.TimeoutExpired:
        os.killpg(host.pid, signal.SIGKILL)
        host.wait(timeout=3)
    for pid in engine_pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("pak", type=Path)
    args = parser.parse_args()
    executable = args.app.resolve() / "Contents/MacOS/openbor-launch"
    pak = args.pak.resolve()
    assert executable.is_file() and pak.is_file()
    root = Path(tempfile.mkdtemp(prefix="openbor-cli-regression-", dir="/tmp"))
    env = os.environ.copy()
    env["OPENBOR_FRONTEND_SUPPORT_ROOT"] = str(root / "library")
    env["OPENBOR_V2_SUPPORT_ROOT"] = str(root / "runtime")

    for options in (["--help"], ["-h"], ["--pak", str(pak), "--help"]):
        result = subprocess.run(
            [str(executable), *options], env=env, capture_output=True,
            text=True, timeout=5, check=True
        )
        assert "OpenBOR Frontend Launcher CLI" in result.stdout
        assert "--logs-dir" in result.stdout
        assert not (root / "library").exists(), "Help initialized the application"
        assert not (root / "runtime").exists(), "Help initialized the engine"
    print("PASS: --help and -h print help and exit without initializing the app")

    for index, flag in enumerate(("--pak", "--launch")):
        run_root = root / f"run-{index}"
        env["OPENBOR_FRONTEND_SUPPORT_ROOT"] = str(run_root / "library")
        env["OPENBOR_V2_SUPPORT_ROOT"] = str(run_root / "runtime")
        logs = run_root / "Custom Logs"
        logs_option = str(logs) + ("/" if index else "")
        frame = run_root / "runtime/Bridge/Frontend/frame.raw"
        bridge_log = frame.parent / "engine-bridge.log"
        host = subprocess.Popen(
            [str(executable), flag, str(pak), "--logs-dir", logs_option,
             "--saves-dir", str(run_root / "Saves"),
             "--screenshots-dir", str(run_root / "Screenshots")],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        try:
            deadline = time.monotonic() + 25
            while time.monotonic() < deadline:
                assert host.poll() is None, "Launcher exited during gameplay"
                if bridge_log.exists() and "Publish #120" in bridge_log.read_text():
                    break
                time.sleep(0.2)
            else:
                raise AssertionError(f"Engine did not publish frames: {run_root}")
            assert frame.exists() and any(frame.read_bytes()), "Empty game frame"
            engine_log = logs / "OpenBorLog.txt"
            assert engine_log.exists() and engine_log.stat().st_size > 0
            assert not (logs / "Logs/OpenBorLog.txt").exists()
            print(f"PASS: {flag} renders and writes logs directly to {logs_option}")
        finally:
            stop_test_processes(host, frame)
    print(f"Test artifacts: {root}")


if __name__ == "__main__":
    main()
