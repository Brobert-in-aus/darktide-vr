"""Offline format/footprint checks for the optional NumPy/Pillow analysis tool."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import numpy as np

spec = importlib.util.spec_from_file_location('analysis', Path(__file__).with_name('analyze-billboard-readback.py'))
analysis = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analysis)

for mantissa in (5, 6):
    bits = np.array([0, 1, 15 << mantissa, 16 << mantissa, 31 << mantissa, (31 << mantissa) | 1])
    values = analysis.unsigned_float(bits, mantissa)
    assert np.allclose(values[:4], [0, 2 ** (-14 - mantissa), 1, 2], atol=0, rtol=0)
    assert np.isinf(values[4]) and np.isnan(values[5])

with tempfile.TemporaryDirectory(prefix='darktidevr-readback-analysis-') as temporary:
    root = Path(temporary).resolve()
    source = root / 'source'
    source.mkdir()
    cases = [(26, 0, (15 << 6) | ((16 << 6) << 11) | ((17 << 5) << 22)),
             (28, 0xff000000, 0xff0000ff), (87, 0xff000000, 0xffff0000)]
    for index, (fmt, before, after) in enumerate(cases, 1):
        stem = f'pair-{index:x}-ff'
        meta = dict(schema_version=1, status='complete', vertex_shader=f'{index:x}', pixel_shader='ff',
                    width=3, height=2, row_pitch=256, format=fmt, bytes=268)
        (source / f'{stem}.json').write_text(json.dumps(meta), encoding='utf-8')
        for which, word in [('before', before), ('after', after)]:
            payload = bytearray(268)
            for row in range(2):
                for column in range(3):
                    struct.pack_into('<I', payload, row * 256 + column * 4, word)
            (source / f'{stem}-{which}.bin').write_bytes(payload)
    reports = analysis.analyze(source, root / 'out')
    assert len(reports) == 3
    assert all(r['changed_pixels'] == 6 and r['changed_bbox_xyxy'] == [0, 0, 3, 2] and
               r['invalid_pixels'] == 0 for r in reports)
    assert reports[0]['maximum_channel_delta'] == 4
    assert reports[1]['maximum_channel_delta'] == reports[2]['maximum_channel_delta'] == 1
    # A short payload must never produce a completed report.
    (source / 'pair-1-ff-after.bin').write_bytes(b'bad')
    try:
        analysis.analyze(source, root / 'invalid')
        raise AssertionError('Truncated capture accepted')
    except ValueError:
        pass
print('PASS: unsigned HDR normals/subnormals/specials, RGBA/BGRA, padded rows, exact changed bounds, truncated payload rejection')
