"""Desktop-only mode must reject XR requests before runtime/device discovery."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    executable = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="darktidevr-no-xr-") as directory:
        environment = dict(os.environ)
        environment["XR_RUNTIME_JSON"] = str(Path(directory) / "missing-runtime.json")
        environment["DARKTIDEVR_TEST_TRANSPORTS"] = "1"
        requests = (["--require-openxr"], ["--require-rendering"],
                    ["--xr-frames", "1"], ["--xr-seconds", "1", "--theatre"],
                    ["--shared-eyes"], ["--synthetic-billboard-sweep"],
                    ["--runtime-d3d11-diagnostics"])
        for request in requests:
            for arguments in (["--no-openxr", *request], [*request, "--no-openxr"]):
                result = subprocess.run([str(executable), *arguments], env=environment,
                                        capture_output=True, text=True, timeout=5,
                                        creationflags=subprocess.CREATE_NO_WINDOW)
                output = result.stdout + result.stderr
                assert result.returncode == 1, (arguments, result.returncode, output)
                assert "--no-openxr cannot be combined with XR requests" in output, output
                assert "openxr." not in output and "d3d12." not in output, output
                assert "runtime_d3d11." not in output, output
    print("PASS: desktop-only conflicts rejected before runtime/device discovery")


if __name__ == "__main__":
    main()
