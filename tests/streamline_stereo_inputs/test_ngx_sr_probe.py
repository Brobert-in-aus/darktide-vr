import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "tools/stereo/read-ngx-sr-probe.py"
spec = importlib.util.spec_from_file_location("sr_reader", SCRIPT)
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)
NATIVE = None
if len(sys.argv) > 2 and sys.argv[1] == "--native":
    NATIVE = sys.argv[2]
    del sys.argv[1:3]


def inputs(call=12, **overrides):
    records = []
    for index, name in enumerate(reader.NAMES):
        data = dict(call=str(call), feature="0000000000001234", lifetime="2",
                    commands="0000000000005678", thread="7", batch="1", present="8",
                    first_call="10", index=str(index), name=name, result="1",
                    resource="0000000000009ABC", described="1", dimension="3",
                    width="1440", height="1600", depth_or_array="1", mips="1", format="28",
                    samples="1", pixels_captured="0", publication="0")
        data.update(overrides)
        records.append("NGX_SR_INPUT " + " ".join(f"{k}={v}" for k, v in data.items()))
    return records


def evaluation(call=12, result="1"):
    return f"NGX_SR_EVAL call={call} result={result} gpu_complete=0 publication=0"


def trace(records, gate=1):
    return reader.HEADER.format(gate=gate) + "\n" + "\n".join(records) + "\n"


class SrObservationReader(unittest.TestCase):
    @unittest.skipUnless(NATIVE, "pass --native with the built SR observation test")
    def test_actual_native_record_formatter(self):
        result = subprocess.run([NATIVE, "--emit-records"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = reader.parse(reader.CONTEXT_HEADER.format(gate=1) + "\n" + result.stdout)
        self.assertEqual(report["complete_calls"], 1)
        observation = report["observations"][0]
        self.assertTrue(observation["context_records_complete"])
        self.assertTrue(observation["stable_pending_eye_tag"])
        self.assertFalse(report["eye_attribution_verified"])
        self.assertTrue(observation["scalar_records_complete"])
        self.assertEqual(observation["scalars"]["Jitter.Offset.X"]["value"], -0.375)
        self.assertTrue(observation["evaluation_succeeded"])
        self.assertEqual([item["status"] for item in observation["inputs"]],
                         ["described"] * 4 + ["query_failed", "null_resource", "null_resource"])
        self.assertEqual(observation["inputs"][0]["descriptor"]["width"], 1440)

    def test_context_changes_ambiguity_and_missing_end_are_not_stable(self):
        before = "NGX_SR_CONTEXT call=12 phase=before available=1 eye=0 pose=42 queued=1 arms=9 resets=0 attribution_verified=0"
        after = before.replace("phase=before", "phase=after")
        header = reader.CONTEXT_HEADER.format(gate=1) + "\n"
        for ending in ("", after.replace("eye=0", "eye=1"),
                       after.replace("pose=42", "pose=43"),
                       after.replace("arms=9", "arms=10"),
                       after.replace("resets=0", "resets=1"),
                       after.replace("eye=0 pose=42 queued=1", "eye=-1 pose=0 queued=2")):
            with self.subTest(ending=ending):
                result = reader.parse(header + before + "\n" + ending)
                self.assertFalse(result["observations"][0]["stable_pending_eye_tag"])
        unknown = before.replace("available=1 eye=0 pose=42 queued=1 arms=9", "available=0 eye=-1 pose=0 queued=0 arms=0")
        result = reader.parse(header + unknown + "\n" + unknown.replace("phase=before", "phase=after"))
        self.assertFalse(result["observations"][0]["stable_pending_eye_tag"])
        for invalid in (before + "\n" + before, before.replace("queued=1", "queued=2"),
                        before.replace("available=1", "available=0"),
                        before.replace("attribution_verified=0", "attribution_verified=1"),
                        before.replace("eye=0", "eye=2"), before.replace("arms=9", "arms=-1")):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                reader.parse(header + invalid)
        with self.assertRaises(ValueError):
            reader.parse(reader.TEMPORAL_HEADER.format(gate=1) + "\n" + before)

    def test_interleaved_success_failure_null_and_evaluation_failure(self):
        first = inputs()
        first[4] = inputs(result="bad00005", resource="ffff", described="0",
                          **{key: "0" for key in reader.DESCRIPTOR})[4]
        first[5] = inputs(resource="0", described="0",
                          **{key: "0" for key in reader.DESCRIPTOR})[5]
        second = inputs(13, thread="8", commands="abcd")
        records = [line for pair in zip(first, second) for line in pair]
        report = reader.parse(trace(records + [evaluation(13, "bad00001"), evaluation()]))
        self.assertEqual(report["complete_calls"], 2)
        self.assertFalse(report["hud_attribution_verified"])
        self.assertFalse(report["gpu_completion_verified"])
        one, two = report["observations"]
        self.assertEqual(one["inputs"][4]["status"], "query_failed")
        self.assertIsNone(one["inputs"][4]["descriptor"])
        self.assertEqual(one["inputs"][5]["status"], "null_resource")
        self.assertFalse(two["evaluation_succeeded"])

    def test_truncation_and_empty_probe_are_not_complete(self):
        for records in ([], inputs(), inputs()[:3], [evaluation()], inputs()[:6] + [evaluation()]):
            with self.subTest(records=len(records)):
                report = reader.parse(trace(records))
                self.assertEqual(report["complete_calls"], 0)
        report = reader.parse(trace(inputs()))
        self.assertIsNone(report["observations"][0]["evaluation_succeeded"])

    def test_ungated_window(self):
        report = reader.parse(trace(inputs(1, batch="0", present="0", first_call="0") +
                                    [evaluation(1)], gate=0))
        self.assertEqual(report["complete_calls"], 1)

    def test_contradictions_and_native_ranges_rejected(self):
        for changes in ({"result": "bad00005"}, {"resource": "0"}, {"described": "0"},
                        {"pixels_captured": "1"}, {"publication": "1"}, {"width": "0"},
                        {"dimension": "9"}, {"mips": "65536"}, {"thread": str(2**32)},
                        {"resource": "1" * 17}, {"lifetime": "0"}, {"feature": "0"},
                        {"batch": "0"}, {"call": "10"}, {"call": "32779"},
                        {"result": "100000000"}, {"name": "HUDLess"}, {"index": "7"}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                reader.parse(trace(inputs(**changes)))

    def test_duplicate_mixed_identity_and_unsupported_records_rejected(self):
        cases = [inputs() + [inputs()[0]], inputs() + [evaluation(), evaluation()],
                 inputs()[:1] + inputs(thread="8")[1:],
                 inputs() + inputs(13, batch="2"),
                 [inputs()[0] + " call=12"], [inputs()[0] + " extra=1"],
                 ["NGX_EVAL call=12"], [evaluation().replace("gpu_complete=0", "gpu_complete=1")]]
        for records in cases:
            with self.subTest(records=records), self.assertRaises(ValueError):
                reader.parse(trace(records))
        with self.assertRaises(ValueError):
            reader.parse(trace(inputs()).replace("schema=1", "schema=2", 1))

    def test_budget_boundary(self):
        records = [evaluation(call) for call in range(1, 65)]
        self.assertEqual(reader.parse(trace(records))["observed_calls"], 64)
        with self.assertRaises(ValueError):
            reader.parse(trace(records + [evaluation(65)]))

    def test_scalar_validation_and_legacy_absence(self):
        scalar = "NGX_SR_SCALAR call=12 name=Reset type=integer queried=1 result=1 valid=1 value=0"
        header = reader.TEMPORAL_HEADER.format(gate=1) + "\n"
        report = reader.parse(header + scalar)
        self.assertFalse(report["observations"][0]["complete"])
        self.assertFalse(report["observations"][0]["scalar_records_complete"])
        for replacement in ("value=nan", "value=2147483648", "value=0.5"):
            with self.assertRaises(ValueError):
                reader.parse(header + scalar.replace("value=0", replacement))
        for invalid in (scalar + "\n" + scalar, scalar.replace("queried=1", "queried=0"),
                        scalar.replace("result=1", "result=bad"), scalar.replace("type=integer", "type=float")):
            with self.assertRaises(ValueError): reader.parse(header + invalid)
        unavailable = scalar.replace("queried=1 result=1 valid=1 value=0", "queried=0 result=0 valid=0 value=unavailable")
        with self.assertRaises(ValueError):
            reader.parse(header + scalar.replace("name=Reset type=integer", "name=Jitter.Offset.X type=float").replace("value=0", "value=1e39"))
        self.assertIsNone(reader.parse(header + unavailable)["observations"][0]["scalars"]["Reset"]["value"])
        self.assertFalse(reader.parse(trace(inputs() + [evaluation()]))["observations"][0]["scalar_records_complete"])

    def test_cli_preserves_source_and_rejects_without_json(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "sr.log"
            for contents, expected in ((trace(inputs() + [evaluation()]), 0), ("bad header\n", 2)):
                source.write_text(contents, encoding="utf-8")
                before = source.read_bytes()
                result = subprocess.run([sys.executable, "-B", str(SCRIPT), str(source)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stderr)
                self.assertEqual(source.read_bytes(), before)
                self.assertEqual(list(Path(directory).iterdir()), [source])
                if expected == 0:
                    report = json.loads(result.stdout)
                    self.assertEqual(report["complete_calls"], 1)
                    self.assertEqual(len(report["source_sha256"]), 64)
                else:
                    self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
