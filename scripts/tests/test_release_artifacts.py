import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from collect_artifacts import collect, version_from_pubspec
from publish_android import main as publish, validate
from verify_android_apk import verify


class ReleaseArtifactsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "app").mkdir()
        (self.root / "app/pubspec.yaml").write_text("version: 0.4.0+12\n", encoding="utf-8")

    def write(self, path, content=b"fixture, not a real APK"):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        return target

    def write_apk(self, filename, entries=None):
        target = self.root / "app/build/app/outputs/flutter-apk" / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        if entries is None:
            entries = {
                "AndroidManifest.xml": b"manifest fixture",
                "assets/flutter_assets/kernel_blob.bin": b"kernel fixture",
                "assets/flutter_assets/isolate_snapshot_data": b"isolate fixture",
                "assets/flutter_assets/vm_snapshot_data": b"vm fixture",
            }
        with zipfile.ZipFile(target, "w") as archive:
            for name, content in entries.items():
                archive.writestr(name, content)
        return target

    def test_signed_download_contract_and_checksum(self):
        self.write_apk("app-release.apk")
        artifact, = collect(self.root, "android", "signed-apk")
        self.assertEqual(artifact.name, "MarketMateMobile_0.4.0+12.apk")
        manifest, validated = validate(self.root / "build/android")
        self.assertEqual(validated, artifact)
        self.assertEqual(set(manifest), {"version", "apk", "checksum", "sha256", "publishedAt"})
        self.assertEqual(manifest["sha256"], hashlib.sha256(artifact.read_bytes()).hexdigest())
        self.assertTrue(manifest["publishedAt"].endswith("Z"))

    def test_debug_build_does_not_generate_public_manifest(self):
        self.write_apk("app-debug.apk")
        artifact, = collect(self.root, "android", "debug-apk")
        self.assertIn("debug", artifact.name)
        self.assertFalse((self.root / "build/android/latest.json").exists())

    def test_incomplete_debug_apk_is_rejected_before_copy(self):
        required = (
            "AndroidManifest.xml",
            "assets/flutter_assets/kernel_blob.bin",
            "assets/flutter_assets/isolate_snapshot_data",
            "assets/flutter_assets/vm_snapshot_data",
        )
        for name in required:
            for empty in (False, True):
                with self.subTest(asset=name, empty=empty):
                    entries = {entry: b"fixture" for entry in required if entry != name}
                    if empty:
                        entries[name] = b""
                    self.write_apk("app-debug.apk", entries)
                    with self.assertRaisesRegex(ValueError, "Incomplete Flutter debug APK"):
                        collect(self.root, "android", "debug-apk")
                    self.assertEqual(list((self.root / "build/android").iterdir()), [])

    def test_tampered_artifact_and_path_traversal_rejected(self):
        self.write_apk("app-release.apk")
        artifact, = collect(self.root, "android", "signed-apk")
        artifact.write_bytes(b"tampered")
        with self.assertRaises(ValueError):
            validate(self.root / "build/android")
        manifest_path = self.root / "build/android/latest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["apk"] = "../other.apk"
        manifest_path.write_text(json.dumps(manifest))
        with self.assertRaises(ValueError):
            validate(self.root / "build/android")

    def test_missing_build_and_wrong_platform_fail(self):
        with self.assertRaises(FileNotFoundError):
            collect(self.root, "android", "signed-apk")
        with self.assertRaises(ValueError):
            collect(self.root, "ios", "signed-apk")

    def test_ios_archive_contains_app_bundle(self):
        self.write("app/build/ios/iphonesimulator/Runner.app/Info.plist", b"plist fixture")
        artifact, = collect(self.root, "ios", "simulator")
        with tarfile.open(artifact) as archive:
            self.assertIn("Runner.app/Info.plist", archive.getnames())

    def test_invalid_version_rejected(self):
        (self.root / "app/pubspec.yaml").write_text("version: ../../bad\n")
        with self.assertRaises(ValueError):
            version_from_pubspec(self.root)

    @patch("verify_android_apk.subprocess.run")
    def test_expected_release_certificate_accepted(self, run):
        expected = "a" * 64
        run.return_value = subprocess.CompletedProcess([], 0, f"Signer #1 certificate SHA-256 digest: {expected}\n")
        self.assertEqual(verify("apksigner", "test.apk", expected.upper()), expected)
        self.assertTrue(run.call_args.kwargs["check"])

    @patch("verify_android_apk.subprocess.run")
    def test_wrong_or_debug_certificate_rejected(self, run):
        expected = "a" * 64
        run.return_value = subprocess.CompletedProcess([], 0, f"Signer #1 certificate SHA-256 digest: {'b' * 64}\n")
        with self.assertRaises(ValueError):
            verify("apksigner", "test.apk", expected)
        run.return_value.stdout = f"Signer #1 certificate SHA-256 digest: {expected}\nCN=Android Debug"
        with self.assertRaises(ValueError):
            verify("apksigner", "test.apk", expected)

    @patch.dict(os.environ, {"GITHUB_REF": "refs/heads/master"}, clear=True)
    @patch("publish_android.subprocess.run")
    def test_publish_gate_defaults_closed_without_network(self, run):
        with self.assertRaises(SystemExit):
            publish()
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
