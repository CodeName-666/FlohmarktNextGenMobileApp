"""Collect Flutter outputs without relocating Flutter's transient build directory."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import tarfile
import zipfile


def version_from_pubspec(root: Path) -> tuple[str, str]:
    source = (root / "app/pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)\+([1-9][0-9]*)\s*$", source, re.M)
    if not match:
        raise ValueError("pubspec.yaml must contain version: MAJOR.MINOR.PATCH+BUILD")
    return match.group(1), match.group(2)


def checksum(path: Path) -> str:
    with path.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    path.with_name(path.name + ".sha256").write_text(f"{digest}  {path.name}\n", encoding="utf-8")
    return digest


def validate_debug_apk(path: Path) -> None:
    required = (
        "AndroidManifest.xml",
        "assets/flutter_assets/kernel_blob.bin",
        "assets/flutter_assets/isolate_snapshot_data",
        "assets/flutter_assets/vm_snapshot_data",
    )
    with zipfile.ZipFile(path) as archive:
        entries = {entry.filename: entry for entry in archive.infolist()}
        missing = [name for name in required
                   if name not in entries or entries[name].is_dir() or entries[name].file_size == 0]
        if missing:
            raise ValueError("Incomplete Flutter debug APK; missing or empty: " + ", ".join(missing))


def collect(root: Path, platform: str, kind: str) -> list[Path]:
    version, build = version_from_pubspec(root)
    output = root / "build" / platform
    output.mkdir(parents=True, exist_ok=True)
    prefix = f"MarketMateMobile_{version}+{build}"
    sources = {
        "debug-apk": ("app/build/app/outputs/flutter-apk/app-debug.apk", "android-debug.apk"),
        "signed-apk": ("app/build/app/outputs/flutter-apk/app-release.apk", "android.apk"),
        "unsigned-apk": ("app/build/app/outputs/flutter-apk/app-release.apk", "android-unsigned.apk"),
        "unsigned-aab": ("app/build/app/outputs/bundle/release/app-release.aab", "android-unsigned.aab"),
        "upload-aab": ("app/build/app/outputs/bundle/release/app-release.aab", "android-upload-signed.aab"),
        "simulator": ("app/build/ios/iphonesimulator/Runner.app", "ios-simulator.app.tar.gz"),
        "unsigned-device": ("app/build/ios/iphoneos/Runner.app", "ios-device-unsigned.app.tar.gz"),
    }
    if kind not in sources or ((platform == "ios") != (kind in ("simulator", "unsigned-device"))):
        raise ValueError("Artifact kind does not match platform")
    relative, suffix = sources[kind]
    source = root / relative
    destination = output / (f"{prefix}.apk" if kind == "signed-apk" else f"{prefix}_{suffix}")
    if not source.exists():
        raise FileNotFoundError(f"Expected Flutter output missing: {source}")
    if kind == "debug-apk":
        validate_debug_apk(source)
    if source.is_dir():
        with tarfile.open(destination, "w:gz", dereference=False) as archive:
            archive.add(source, arcname=source.name)
    else:
        shutil.copy2(source, destination)
    digest = checksum(destination)
    metadata = {"version": version, "buildNumber": int(build), "platform": platform,
                "kind": kind, "artifact": destination.name, "sha256": digest}
    destination.with_name(destination.name + ".json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    if kind == "signed-apk":
        manifest = {"version": f"{version}+{build}", "apk": destination.name,
                    "checksum": destination.name + ".sha256", "sha256": digest,
                    "publishedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")}
        (output / "latest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return [destination]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("android", "ios"))
    parser.add_argument("kind")
    args = parser.parse_args()
    for result in collect(Path(__file__).resolve().parents[1], args.platform, args.kind):
        print(result)
