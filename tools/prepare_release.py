"""Package the validated launcher and historical ZIPs without personal/game data."""
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
FINAL = ROOT / "build/final"
APP = ROOT / "build/frontend/OpenBOR Frontend Launcher.app"


def excluded(name):
    lower = name.lower()
    return (lower.endswith((".pak", ".sav", ".cfg", ".log", ".sqlite", ".boot", ".entityvars"))
            or any(segment in lower for segment in ("/logs/", "/saves/", "/screenshots/"))
            or lower.endswith(("/openborlog.txt", "/scriptlog.txt")))


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def prepare():
    dated = sorted(path for path in FINAL.glob("*.zip")
                   if re.fullmatch(r"OpenBOR Frontend Launcher \d{8}-\d{4}\.zip", path.name))
    if not dated:
        raise SystemExit("No versioned launcher packages found")
    latest = dated[-1]
    stamp = re.search(r"\d{8}-\d{4}", latest.name).group()
    # Refuse to label a different build as the validated latest package.
    with zipfile.ZipFile(latest) as archive:
        for suffix in ("/Contents/MacOS/OpenBORFrontend",
                       "/Contents/Resources/Engine/OpenBOR.app/Contents/MacOS/OpenBOR-bin"):
            entries = [name for name in archive.namelist() if name.endswith(suffix) and not name.startswith("__MACOSX/")]
            if len(entries) != 1 or hashlib.sha256(archive.read(entries[0])).hexdigest() != digest(APP / suffix.lstrip("/")):
                raise SystemExit("Latest versioned package does not match the current built app")
    with (APP / "Contents/Info.plist").open("rb") as stream:
        version = plistlib.load(stream)["CFBundleShortVersionString"]
    output = ROOT / "build/publish" / f"v{version}-{stamp}"
    output.mkdir(parents=True, exist_ok=True)
    current = output / f"OpenBOR-Frontend-Launcher-V{version}-{stamp}-macOS-arm64.zip"
    subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(APP), str(current)], check=True)
    with zipfile.ZipFile(current) as archive:
        if any(excluded(name) for name in archive.namelist()):
            current.unlink()
            raise SystemExit("Current app contains game/runtime data; distribution refused")
    historical = [path for path in sorted(FINAL.glob("*.zip")) if path != latest]
    history = output / f"Historical-Launcher-Builds-through-{stamp}.zip"
    manifest = {"current_build": stamp, "version": version, "historical_count": len(historical), "builds": []}
    with zipfile.ZipFile(history, "w", compression=zipfile.ZIP_STORED, allowZip64=True) as outer:
        for path in historical:
            with zipfile.ZipFile(path) as archive:
                omissions = [item.filename for item in archive.infolist() if excluded(item.filename)]
                asset = path
                if omissions:
                    asset = output / (path.stem + "-clean.zip")
                    with zipfile.ZipFile(asset, "w", compression=zipfile.ZIP_DEFLATED) as cleaned:
                        for item in archive.infolist():
                            if not excluded(item.filename):
                                cleaned.writestr(item, archive.read(item.filename))
            outer.write(asset, arcname=asset.name)
            manifest["builds"].append({"file": asset.name, "sha256": digest(asset), "removed_entries": len(omissions)})
    manifest["packages"] = [{"file": path.name, "sha256": digest(path)} for path in (current, history)]
    (output / "release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (output / "SHA256SUMS.txt").write_text("".join(f"{digest(path)}  {path.name}\n" for path in (current, history)), encoding="ascii")
    print(f"Current package: {current.name}")
    print(f"Historical builds: {len(historical)} ({history.stat().st_size // (1024 * 1024)} MiB)")
    print(f"Output: {output}")


if __name__ == "__main__":
    prepare()
