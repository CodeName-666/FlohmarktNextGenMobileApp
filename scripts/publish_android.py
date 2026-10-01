"""Publish only a verified APK through the separately provisioned mobile SSH command."""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.parse
import urllib.request

from verify_android_apk import verify

STAGING = "/srv/marketmate/prod/releases-staging/mobile/android"
PUBLIC_BASE = "https://api.preview.market-mate.de/uploads/releases/mobile/android"


def validate(directory: Path) -> tuple[dict, Path]:
    manifest = json.loads((directory / "latest.json").read_text(encoding="utf-8"))
    version = manifest.get("version", "")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?\+[1-9][0-9]*", version):
        raise ValueError("Invalid release version")
    filename = f"MarketMateMobile_{version}.apk"
    if manifest.get("apk") != filename or manifest.get("checksum") != filename + ".sha256":
        raise ValueError("Invalid mobile release filenames")
    artifact = directory / filename
    with artifact.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    expected = f"{digest}  {filename}\n"
    if manifest.get("sha256") != digest or (directory / manifest["checksum"]).read_text(encoding="utf-8") != expected:
        raise ValueError("APK, manifest and checksum do not match")
    return manifest, artifact


def main() -> None:
    if os.environ.get("GITHUB_REF") != "refs/heads/master":
        raise SystemExit("Publishing is restricted to master")
    for gate in ("MOBILE_SERVER_PUBLISH_ENABLED", "MOBILE_SERVER_CONTRACT_READY"):
        if os.environ.get(gate) != "true":
            raise SystemExit(f"Publish gate is closed: {gate}")
    required = ("MARKETMATE_VPS_HOST", "MARKETMATE_MOBILE_RELEASES_SSH_USER",
                "MARKETMATE_MOBILE_RELEASES_SSH_KEY", "MARKETMATE_MOBILE_RELEASES_KNOWN_HOSTS",
                "ANDROID_APP_CERT_SHA256", "APKSIGNER")
    if any(not os.environ.get(name) for name in required):
        raise SystemExit("Mobile publishing configuration is incomplete")
    host = os.environ["MARKETMATE_VPS_HOST"]
    user = os.environ["MARKETMATE_MOBILE_RELEASES_SSH_USER"]
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", host) or not re.fullmatch(r"[a-z_][a-z0-9_-]*", user):
        raise SystemExit("Invalid configured SSH host or user")
    directory = Path(__file__).resolve().parents[1] / "build/android"
    manifest, artifact = validate(directory)
    verify(os.environ["APKSIGNER"], str(artifact), os.environ["ANDROID_APP_CERT_SHA256"])
    with tempfile.TemporaryDirectory(prefix="marketmate-mobile-") as temporary:
        key = Path(temporary) / "key"
        known_hosts = Path(temporary) / "known_hosts"
        key.write_text(os.environ["MARKETMATE_MOBILE_RELEASES_SSH_KEY"] + "\n", encoding="utf-8")
        key.chmod(0o600)
        known_hosts.write_text(os.environ["MARKETMATE_MOBILE_RELEASES_KNOWN_HOSTS"] + "\n", encoding="utf-8")
        options = ["-i", str(key), "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
                   "-o", "StrictHostKeyChecking=yes", "-o", f"UserKnownHostsFile={known_hosts}"]
        remote = f"{user}@{host}"
        subprocess.run(["scp", "-O", *options, str(artifact), str(directory / manifest["checksum"]),
                        f"{remote}:{STAGING}/"], check=True)
        # The server owns the atomic installation and latest-manifest update.
        subprocess.run(["ssh", *options, remote, "publish-mobile-android"], check=True)
    # Verify actual public bytes and metadata; a transport success alone is insufficient.
    with urllib.request.urlopen(PUBLIC_BASE + "/latest.json", timeout=30) as response:
        published = json.load(response)
    if any(published.get(field) != manifest[field] for field in ("version", "apk", "checksum", "sha256")):
        raise RuntimeError("Published mobile manifest does not match this build")
    with urllib.request.urlopen(PUBLIC_BASE + "/" + urllib.parse.quote(manifest["checksum"]), timeout=30) as response:
        if response.read() != (directory / manifest["checksum"]).read_bytes():
            raise RuntimeError("Published checksum sidecar does not match")
    with urllib.request.urlopen(PUBLIC_BASE + "/" + urllib.parse.quote(manifest["apk"]), timeout=60) as response:
        digest = hashlib.file_digest(response, "sha256").hexdigest()
    if digest != manifest["sha256"]:
        raise RuntimeError("Published APK does not match")
    print("Signed Android APK published and public download verified")


if __name__ == "__main__":
    main()
