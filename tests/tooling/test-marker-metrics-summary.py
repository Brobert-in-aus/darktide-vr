import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/stereo/summarize-marker-metrics.py"
spec = importlib.util.spec_from_file_location("marker_summary", SCRIPT)
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)
START = summary.PREFIX + "started=true pass_budget=60"
END = summary.PREFIX + "complete=true"


def row(**changes):
    fields = dict(kind="interaction", left=2, right=2, matched=2, shape=0, font=0,
                  scale=0, alpha=0, color_alpha=0, kind_mismatch=0, max_anchor_delta=30.0,
                  incomplete="false", text_layout=0, text_measured=1, layer=0,
                  start_layer=0, max_layer_delta=0.0, offset_depth=0,
                  max_offset_depth_delta=0.0, input_geometry_only="true")
    fields.update(changes)
    return "[Lua] [INFO] " + summary.PREFIX + " ".join(f"{k}={v}" for k, v in fields.items())


class MarkerSummary(unittest.TestCase):
    def test_nonempty_inputs_and_expected_stereo_translation(self):
        report = summary.summarize(["unrelated private log line", START, row(), END])
        run, = report["sessions"]
        self.assertEqual(run["termination"], "budget_complete")
        self.assertTrue(run["start_observed"])
        measured = run["kinds"]["interaction"]
        self.assertEqual(measured["matching_input_pairs"], 1)
        self.assertEqual(measured["maximum_deltas"]["max_anchor_delta"], 30)
        self.assertFalse(report["raster_bounds_verified"])
        self.assertEqual(report["visual_acceptance"], "unverified")
        self.assertNotIn("private", json.dumps(report))

    def test_empty_and_incomplete_never_count_as_matching_evidence(self):
        run = summary.summarize([START, row(left=0, right=0, matched=0, text_measured=0),
            row(incomplete="true"), row(shape=1, font=1),
            summary.PREFIX + "kind=tag unmatched=true", END])["sessions"][0]
        measured = run["kinds"]["interaction"]
        self.assertEqual(measured["empty_pairs"], 1)
        self.assertEqual(measured["incomplete_pairs"], 1)
        self.assertEqual(measured["matching_input_pairs"], 0)
        self.assertEqual(measured["counters"]["shape"], 1)
        self.assertEqual(run["kinds"]["tag"]["unmatched_scopes"], 1)
        self.assertEqual(run["minimum_observed_scopes"], 7)

    def test_interruptions_and_missing_start_are_separate(self):
        runs = summary.summarize([row(), START, row(kind="tag"), START, END,
                                  row(kind="markers")])["sessions"]
        self.assertEqual([r["termination"] for r in runs],
                         ["new_start", "new_start", "budget_complete", "log_end"])
        self.assertEqual([r["start_observed"] for r in runs], [False, True, True, False])
        self.assertEqual(runs[2]["kinds"], {})
        self.assertNotIn("interaction", runs[1]["kinds"])

    def test_all_differences_and_maxima_remain_separate(self):
        changes = {name: 1 for name in summary.DIFFERENCES}
        changes.update(max_anchor_delta=10, max_layer_delta=4, max_offset_depth_delta=8)
        run = summary.summarize([row(**changes), row(max_anchor_delta=20)])["sessions"][0]
        measured = run["kinds"]["interaction"]
        self.assertTrue(all(measured["counters"][name] == 1 for name in summary.DIFFERENCES))
        self.assertEqual(measured["maximum_deltas"],
                         dict(max_anchor_delta=20, max_layer_delta=4, max_offset_depth_delta=8))
        self.assertEqual(measured["matching_input_pairs"], 1)

    def test_malformed_and_impossible_evidence_is_rejected(self):
        invalid = [row() + " left=2", row(kind="unknown"), row(matched=3), row(shape=3),
                   row(text_layout=2), row(left=3), row(kind_mismatch=1),
                   row(max_anchor_delta="nan"), row(max_layer_delta="inf"),
                   row(max_offset_depth_delta=-1), row(incomplete="False"),
                   row(left=-1), row(input_geometry_only="false"),
                   row().replace(" offset_depth=0", ""), row() + " unknown=1",
                   summary.PREFIX + "started=false pass_budget=60",
                   summary.PREFIX + "started=true pass_budget=241",
                   summary.PREFIX + "complete=false",
                   summary.PREFIX + "kind=tag unmatched=false"]
        for record in invalid:
            with self.subTest(record=record), self.assertRaisesRegex(ValueError, "line 2"):
                summary.summarize(["noise", record])
        with self.assertRaises(ValueError):
            summary.summarize([START.replace("60", "2"), row(), row()])
        with self.assertRaises(ValueError):
            summary.summarize(["no diagnostic here"])

    def test_truncation_keeps_partial_counts_without_certification(self):
        run = summary.summarize([row(left=129, right=129, matched=128, incomplete="true")])["sessions"][0]
        measured = run["kinds"]["interaction"]
        self.assertEqual(measured["counters"]["matched"], 128)
        self.assertEqual(measured["matching_input_pairs"], 0)

    def test_cli_preserves_bad_output_and_binds_valid_input_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "metrics.log"
            output = Path(temporary) / "report.json"
            source.write_text(row(left=-1), encoding="utf-8")
            output.write_text("preserve", encoding="utf-8")
            result = subprocess.run([sys.executable, "-B", str(SCRIPT), str(source),
                "--output", str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(output.read_text(), "preserve")
            source.write_text(START + "\n" + row() + "\n" + END, encoding="utf-8-sig")
            result = subprocess.run([sys.executable, "-B", str(SCRIPT), str(source),
                "--output", str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(output.read_text())
            self.assertEqual(report["input_sha256"], summary.hashlib.sha256(source.read_bytes()).hexdigest())
            self.assertEqual(report["input_bytes"], source.stat().st_size)
            before = source.read_bytes()
            result = subprocess.run([sys.executable, "-B", str(SCRIPT), str(source),
                "--output", str(source)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(source.read_bytes(), before)

    def test_actual_lua_observer_log_roundtrip(self):
        validator = ROOT / "build/dependencies/luajit/src/luajit.exe"
        if not validator.is_file():
            self.skipTest("Pinned Windows LuaJIT is unavailable")
        module = ROOT / "mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_marker_metrics.lua"
        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary) / "observer.lua"
            log = Path(temporary) / "observer.log"
            fixture.write_text('''local metrics=dofile(arg[1])
local file=assert(io.open(arg[2],'w'))
local commands={}
local class={script_draw_bitmap=function()return 1,nil,3 end}
local mod={hook=function(_,target,name,hook)
    local original=target[name];target[name]=function(...)return hook(original,...)end
end,command=function(_,name,_,fn)commands[name]=fn end,
info=function(_,format,...)file:write(string.format(format,...),'\\n')end}
metrics.install(mod,class)
local renderer={scale=1};local owner={}
commands.dtvr_marker_metrics()
for frame=1,30 do for eye=1,2 do
    metrics.draw(renderer,'interaction',owner,frame,eye,nil,function()
        if frame%2==0 then
            local a,b,c=class.script_draw_bitmap(renderer,'material',{eye*20,30,7},{100,20,0},{255,1,1,1})
            assert(a==1 and b==nil and c==3)
        end
    end)
end end
assert(file:close())
''', encoding="utf-8")
            result = subprocess.run([str(validator), str(fixture), str(module), str(log)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            run, = summary.summarize(log.read_text().splitlines())["sessions"]
            self.assertEqual(run["termination"], "budget_complete")
            self.assertEqual(run["minimum_observed_scopes"], 60)
            measured = run["kinds"]["interaction"]
            self.assertEqual(measured["pairs"], 30)
            self.assertEqual(measured["matching_input_pairs"], 15)
            self.assertEqual(measured["empty_pairs"], 15)
            self.assertEqual(measured["maximum_deltas"]["max_anchor_delta"], 20)


if __name__ == "__main__":
    unittest.main()
