import importlib.util
from datetime import datetime, timezone, timedelta
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("load", Path(__file__).resolve().parents[2] /
                                            "tools/stereo/analyze-synthetic-gpu-load.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
HEADER = "timestamp, index, utilization.gpu [%], power.draw [W], clocks.current.graphics [MHz], clocks.current.memory [MHz]\n"


class LoadTests(unittest.TestCase):
    def test_window_unknown_and_timezone(self):
        text = HEADER + "2026/09/10 12:00:00.000, 0, 100 %, 400 W, 2000 MHz, 10000 MHz\n" + \
            "2026/09/10 12:00:01.000, 0, 50 %, N/A, 2000 MHz, 10000 MHz\n" + \
            "2026/09/10 12:00:02.000, 0, 60 %, 200 W, 2000 MHz, 10000 MHz\n"
        start = datetime(2026,9,10,2,0,0,500000,tzinfo=timezone.utc)
        r = tool.summarize(text,start,start+timedelta(seconds=1),10)["metrics"]
        self.assertEqual(r["utilization.gpu [%]"]["time_weighted_sample_mean"],55)
        self.assertEqual(r["power.draw [W]"]["time_weighted_sample_mean"],200)
        self.assertEqual(r["power.draw [W]"]["coverage_fraction"],0.5)

    def test_missing_intervals_and_corruption(self):
        row = "2026/09/10 12:00:00.000, 0, 50 %, 200 W, 2000 MHz, 10000 MHz\n"
        start = datetime(2026,9,10,2,tzinfo=timezone.utc)
        r = tool.summarize(HEADER+row+row.replace("12:00:00", "12:00:10"),start,start+timedelta(seconds=10),10)
        self.assertIsNone(r["metrics"]["power.draw [W]"]["time_weighted_sample_mean"])
        with self.assertRaises(ValueError): tool.summarize(HEADER+row+row,start,start+timedelta(seconds=1),10)
        for bad in ("nan W", "-1 W", "oops"):
            with self.assertRaises(ValueError): tool.reading(bad,"W")


if __name__ == "__main__": unittest.main()
