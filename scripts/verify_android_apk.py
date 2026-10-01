"""Verify a release APK against the configured, stable app-signing identity."""

import os
import re
import subprocess
import sys


def normalize_fingerprint(value: str) -> str:
    fingerprint = value.replace(":", "").lower().strip()
    if not re.fullmatch(r"[0-9a-f]{64}", fingerprint):
        raise ValueError("ANDROID_APP_CERT_SHA256 must be a SHA-256 certificate fingerprint")
    return fingerprint


def verify(apksigner: str, apk: str, expected: str) -> str:
    fingerprint = normalize_fingerprint(expected)
    result = subprocess.run([apksigner, "verify", "--verbose", "--print-certs", apk],
                            check=True, capture_output=True, text=True)
    actual = re.findall(r"Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)", result.stdout)
    if len(actual) != 1 or actual[0].lower() != fingerprint:
        raise ValueError("APK certificate does not match the configured app-signing identity")
    if "Android Debug" in result.stdout:
        raise ValueError("Debug certificate cannot be published")
    return fingerprint


if __name__ == "__main__":
    verify(sys.argv[1], sys.argv[2], os.environ.get("ANDROID_APP_CERT_SHA256", ""))
    print("APK signature and app-signing certificate verified")
