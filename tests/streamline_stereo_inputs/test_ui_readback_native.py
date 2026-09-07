"""Read actual isolated native BMP/log outputs through the Python verifier."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile

spec = importlib.util.spec_from_file_location("generated_ui", Path(__file__).resolve().parents[2] /
    "tools/stereo/compare-dlss-generated-ui.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory(prefix="darktidevr-ui-roundtrip-") as directory:
    subprocess.run([str(Path(sys.argv[1]).resolve())], cwd=directory, check=True, timeout=15)
    logs = list(Path(directory).glob("ui-readback-test-*/*.log"))
    assert len(logs) == 1
    stem = logs[0].with_suffix("")
    owner = module.records(logs[0], "UI_READBACK_MATCH")[0]
    # Generated output metadata is a fixture; this test exercises native UI
    # export -> BMP decoding -> RGBA checksum, not NGX or live frame matching.
    output = Path(directory) / "generated.bmp"
    record = (f"pose={owner['pose']} left_scene={owner['left_scene']} right_scene={owner['right_scene']} "
              "left_call=20 right_call=21 source=fixture owned=fixture readback=fixture "
              "width=4 height=2 row_pitch=256 bytes=272 left_hash=1 right_hash=2 result=0x00000000\n")
    output.with_suffix(".log").write_text("NGX_COPY phase=staged " + record + "NGX_COPY phase=exported " + record)
    identity = module.verify_match(stem, output)
    assert identity["ui_content_evidence"] == "native_rgba_checksums"
    for eye in ("left", "right"):
        ui = module.ui_alpha.read_rgba(f"{stem}-{eye}-ui.bmp")
        module.verify_ui_content(identity, eye, ui)
        ui[0, 0, 3] ^= 1
        try:
            module.verify_ui_content(identity, eye, ui)
        except ValueError as error:
            assert "UI RGBA content" in str(error)
        else:
            raise AssertionError("Altered native UI alpha was accepted")
print("ui_readback_native_roundtrip=pass native_export bitmap_decode rgba_hash alpha_corruption")
