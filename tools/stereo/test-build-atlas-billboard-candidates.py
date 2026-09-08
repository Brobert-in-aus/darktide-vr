"""Builder output ownership tests; compiler and interface gate are test doubles."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "builder", Path(__file__).with_name("build-atlas-billboard-candidates.py"))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class OutputOwnership(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.output = self.root / "candidate"
        self.dxc = self.root / "dxc.exe"
        self.dxc.write_bytes(b"test compiler identity")
        self.argv = ["builder", "--dxc", str(self.dxc), "--original-directory", str(self.root),
                     "--native-capture", "unused.dll", "--reflection-library", "unused-reflection.dll",
                     "--output", str(self.output)]
        self.hash = builder.sha256

    def fake_hash(self, path):
        # Fake only the captured originals; source/compiler/output hashes remain
        # real file checksums. No captured binaries or game files are touched.
        if path.parent == self.root and path.name.startswith("vs-"):
            return builder.ORIGINALS[path.stem[3:]]
        return self.hash(path)

    def fake_run(self, command, check):
        self.assertTrue(check)
        if command[0] == str(self.dxc):
            Path(command[command.index("-Fo") + 1]).write_bytes(b"fixture shader")
        else:
            self.assertEqual(command.count("--pair"), 6)
            Path(command[command.index("--output") + 1]).write_text("{}")

    def run_builder(self, run=None, digest=None):
        with patch.object(sys, "argv", self.argv), \
                patch.object(builder, "sha256", side_effect=digest or self.fake_hash), \
                patch.object(builder.subprocess, "run", side_effect=run or self.fake_run):
            return builder.main()

    def test_preserve_every_existing_destination(self):
        for name in (None, "partial.stock.dxil", "build.json"):
            with self.subTest(name=name):
                self.output = self.root / f'existing-{name or "empty"}'
                self.argv[-1] = str(self.output)
                self.output.mkdir()
                if name:
                    (self.output / name).write_bytes(b"prior evidence")
                with self.assertRaises(FileExistsError):
                    self.run_builder(run=lambda *args, **kwargs: self.fail("compiler was invoked"))
                if name:
                    self.assertEqual((self.output / name).read_bytes(), b"prior evidence")
                    (self.output / name).unlink()
                self.output.rmdir()

    def test_exclusive_claim_after_original_validation(self):
        last = next(reversed(builder.ORIGINALS))

        def race(path):
            value = self.fake_hash(path)
            if path.name == f"vs-{last}.bin":
                self.output.mkdir()
                (self.output / "other-run").write_bytes(b"owned elsewhere")
            return value

        with self.assertRaises(FileExistsError):
            self.run_builder(digest=race, run=lambda *args, **kwargs: self.fail("compiler was invoked"))
        self.assertEqual((self.output / "other-run").read_bytes(), b"owned elsewhere")

    def test_failed_build_has_no_success_receipt_and_cannot_be_overwritten(self):
        def fail(command, check):
            Path(command[command.index("-Fo") + 1]).write_bytes(b"partial evidence")
            raise subprocess.CalledProcessError(1, command)

        with self.assertRaises(subprocess.CalledProcessError):
            self.run_builder(run=fail)
        self.assertFalse((self.output / "build.json").exists())
        before = {p.name: p.read_bytes() for p in self.output.iterdir()}
        with self.assertRaises(FileExistsError):
            self.run_builder()
        self.assertEqual({p.name: p.read_bytes() for p in self.output.iterdir()}, before)

    def test_fresh_output_records_all_six_candidates(self):
        self.assertEqual(self.run_builder(), 0)
        receipt = json.loads((self.output / "build.json").read_text())
        self.assertEqual(len(receipt["candidates"]), 6)
        self.assertFalse(receipt["deployed"])
        self.assertFalse(receipt["worn_acceptance"])
        for item in receipt["candidates"]:
            artifact = self.output / f'vs-{item["identity"]}.{item["profile"]}.dxil'
            self.assertEqual(item["shader_sha256"], self.hash(artifact))
            self.assertFalse((self.output / f'vs-{item["identity"]}.dxil').exists())


if __name__ == "__main__":
    unittest.main()
