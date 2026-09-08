import importlib.util
import io
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[2] / "tools/stereo/summarize-vdxr-trace.py"
spec = importlib.util.spec_from_file_location("vdxr_trace", path)
trace = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trace)


def event(time, opcode, activity="{a}", name="WaitForAsyncSubmissionIdle", pid=10, thread=20, running="1"):
    return f'''<Event xmlns="{trace.NS['e']}"><System>
      <Provider Guid="{trace.PROVIDER}"/><Opcode>{opcode}</Opcode>
      <TimeCreated RawTime="{time}"/><Execution ProcessID="{pid}" ThreadID="{thread}"/>
      <Correlation ActivityID="{activity}"/></System>
      <EventData><Data Name="DoRunningStart">{running}</Data></EventData>
      <RenderingInfo><Task>{name}</Task></RenderingInfo></Event>'''


def time(fraction):
    return 10_000_000 + int(fraction.ljust(7, "0"))


def analyze(*items):
    header = f'''<Event xmlns="{trace.NS['e']}"><EventData>
      <Data Name="EventsLost">0</Data><Data Name="StartTime">100</Data>
      <Data Name="BufferSize">1024</Data><Data Name="PerfFreq">10000000</Data>
      <Data Name="ReservedFlags">1</Data></EventData></Event>'''
    return trace.summarize(io.StringIO("<Events>" + header + "".join(items) + "</Events>"), 10)


class VdxrTrace(unittest.TestCase):
    def test_clock_precision_process_filter_and_mode_groups(self):
        result = analyze(event(time("0000000"), 1),
                         event(time("0005000"), 2),
                         event(time("0010000"), 1, "{b}", running="0"),
                         event(time("0020000"), 2, "{b}", running="0"),
                         event(time("0030000"), 1, "{c}", pid=11))
        self.assertEqual(result["activities"]["WaitForAsyncSubmissionIdle"]["mean_ms"], 0.75)
        self.assertEqual(result["retained_event_span_seconds"], 0.002)
        self.assertEqual({r["running_start"]: r["mean_ms"] for r in result["activity_groups"]},
                         {"0": 1.0, "1": 0.5})
        tiny = analyze(event(time("0000000"), 1), event(time("0000001"), 2))
        self.assertEqual(tiny["activities"]["WaitForAsyncSubmissionIdle"]["mean_ms"], 0.0001)
        with self.assertRaisesRegex(ValueError, "tracerpt -rts"):
            analyze(event(time("0000000"), 1).replace('RawTime=', 'SystemTime='))

    def test_nested_and_cross_thread_activities_remain_separate(self):
        result = analyze(event(time("0000000"), 1, name="parent"),
                         event(time("0001000"), 1, "{b}", name="child"),
                         event(time("0002000"), 2, "{b}", name="child", thread=21),
                         event(time("0003000"), 2, name="parent"))
        self.assertEqual(result["activities"]["parent"]["mean_ms"], 0.3)
        self.assertEqual(result["activities"]["child"]["mean_ms"], 0.1)
        child = next(row for row in result["activity_groups"] if row["name"] == "child")
        self.assertEqual((child["start_thread"], child["end_thread"]), ("20", "21"))

    def test_incomplete_invalid_and_circular_capture(self):
        header = f'''<Event xmlns="{trace.NS['e']}"><EventData>
          <Data Name="EventsLost">0</Data><Data Name="StartTime">100</Data>
          <Data Name="BufferSize">1024</Data><Data Name="BuffersWritten">2048</Data>
          <Data Name="MaxFileSize">1</Data><Data Name="LogFileMode">0x2</Data>
          </EventData></Event>'''
        result = analyze(header, event(time("0000000"), 2),
                         event(time("0002000"), 1), event(time("0001000"), 2),
                         event(time("0003000"), 1, "{b}"), event(time("0004000"), 1, "{b}"),
                         event(time("0005000"), 2, "{b}"), event(time("0006000"), 1, "{c}"),
                         event(time("0007000"), 1, trace.ZERO_ACTIVITY), event(-1, 1, "{d}"))
        self.assertTrue(result["circular_file"] and result["circular_overwrite_indicated"])
        self.assertEqual(result["trace_header"]["EventsLost"], 0)
        self.assertEqual(result["activities"]["WaitForAsyncSubmissionIdle"]["samples"], 1)
        self.assertEqual(result["excluded_activities"], {"stop_without_start": 1, "negative_duration": 1,
                         "duplicate_start": 1, "start_without_stop": 1,
                         "missing_activity_identity": 1, "invalid_timestamp": 1})
        self.assertIsNone(analyze()["retained_event_span_seconds"])


if __name__ == "__main__":
    unittest.main()
