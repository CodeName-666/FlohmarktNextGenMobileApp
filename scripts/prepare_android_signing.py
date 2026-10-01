"""Materialize a CI signing key only in the runner's temporary directory."""

import base64
import os
from pathlib import Path


def main() -> None:
    required = ("KEYSTORE_BASE64", "ANDROID_KEY_ALIAS", "ANDROID_STORE_PASSWORD", "ANDROID_KEY_PASSWORD")
    if any(not os.environ.get(name) for name in required):
        raise SystemExit("Incomplete Android signing secrets")
    target = Path(os.environ["RUNNER_TEMP"]) / "marketmate-signing.jks"
    target.write_bytes(base64.b64decode(os.environ["KEYSTORE_BASE64"], validate=True))
    target.chmod(0o600)
    with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as environment:
        environment.write(f"ANDROID_KEYSTORE_PATH={target.as_posix()}\n")


if __name__ == "__main__":
    main()
