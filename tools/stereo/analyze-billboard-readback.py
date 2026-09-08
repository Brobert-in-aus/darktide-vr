"""Decode completed diagnostic draw copies; no game interaction or image synthesis."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import numpy as np
from PIL import Image


def unsigned_float(bits, mantissa_bits):
    mantissa = bits & ((1 << mantissa_bits) - 1)
    exponent = bits >> mantissa_bits
    values = np.ldexp(1.0 + mantissa.astype(np.float64) / (1 << mantissa_bits),
                      exponent.astype(np.int32) - 15)
    values = np.where(exponent == 0,
                      np.ldexp(mantissa.astype(np.float64), -14 - mantissa_bits), values)
    return np.where(exponent == 31, np.where(mantissa == 0, np.inf, np.nan), values)


def decode(payload, width, height, stride, fmt):
    words = np.ndarray((height, width), dtype='<u4', buffer=payload, strides=(stride, 4))
    if fmt == 26:
        return np.stack((unsigned_float(words & 0x7ff, 6),
                         unsigned_float((words >> 11) & 0x7ff, 6),
                         unsigned_float(words >> 22, 5)), axis=-1)
    channels = np.stack([(words >> shift) & 255 for shift in (0, 8, 16, 24)], axis=-1) / 255.0
    return channels if fmt == 28 else channels[:, :, [2, 1, 0, 3]]


def preview(values, hdr):
    rgb = np.nan_to_num(values[:, :, :3], nan=0.0, posinf=0.0, neginf=0.0)
    if hdr:
        rgb = np.maximum(rgb, 0)
        rgb = rgb / (1 + rgb)
        rgb = np.where(rgb <= 0.0031308, rgb * 12.92, 1.055 * rgb ** (1 / 2.4) - 0.055)
    return np.round(np.clip(rgb, 0, 1) * 255).astype(np.uint8)


def analyze(source: Path, output: Path):
    records = sorted(source.glob('pair-*.json'))
    if not records:
        raise ValueError('No completed pair metadata; missing captures are not visual evidence')
    output.mkdir(parents=True, exist_ok=False)
    reports = []
    for record in records:
        match = re.fullmatch(r'pair-([0-9a-f]{1,16})-([0-9a-f]{1,16})', record.stem)
        if not match:
            raise ValueError('Unexpected pair filename')
        data = json.loads(record.read_text(encoding='utf-8'))
        if data.get('schema_version') != 1 or data.get('status') != 'complete':
            raise ValueError('Incomplete or unknown capture schema')
        if any(int(data[name], 16) != int(match[group], 16)
               for name, group in [('vertex_shader', 1), ('pixel_shader', 2)]):
            raise ValueError('Shader identity does not match filename')
        width, height, stride, fmt, size = (data[key] for key in
                                           ('width', 'height', 'row_pitch', 'format', 'bytes'))
        if any(type(value) is not int for value in (width, height, stride, fmt, size)) or not (
            0 < width <= 4096 and 0 < height <= 4096 and stride >= width * 4 and
            stride % 256 == 0 and (height - 1) * stride + width * 4 <= size <= height * stride and
            size <= 32 * 1024 * 1024 and fmt in (26, 28, 87)
        ):
            raise ValueError('Invalid or unbounded footprint')
        arrays, hashes = [], {}
        for which in ('before', 'after'):
            raw = (source / f'{record.stem}-{which}.bin').read_bytes()
            if len(raw) != size:
                raise ValueError('Payload size differs from completed metadata')
            hashes[which] = hashlib.sha256(raw).hexdigest()
            values = decode(raw, width, height, stride, fmt)
            arrays.append(values)
            Image.fromarray(preview(values, fmt == 26)).save(output / f'{record.stem}-{which}.png')
        valid = np.isfinite(arrays[0]).all(axis=-1) & np.isfinite(arrays[1]).all(axis=-1)
        with np.errstate(invalid='ignore'):
            delta = np.max(np.abs(arrays[1] - arrays[0]), axis=-1)
        delta = np.where(valid, delta, 0)
        changed = delta > 1e-6
        # Keep attachment-wide evidence, but distinguish color from alpha-only
        # writes: neither alone establishes ownership of a visible effect.
        with np.errstate(invalid='ignore'):
            rgb_delta = np.max(np.abs(arrays[1][:, :, :3] - arrays[0][:, :, :3]), axis=-1)
        rgb_valid = (np.isfinite(arrays[0][:, :, :3]).all(axis=-1) &
                     np.isfinite(arrays[1][:, :, :3]).all(axis=-1))
        rgb_changed = rgb_valid & (rgb_delta > 1e-6)
        alpha_changed = np.zeros((height, width), dtype=bool)
        if fmt != 26:
            alpha_changed = np.abs(arrays[1][:, :, 3] - arrays[0][:, :, 3]) > 1e-6
        ys, xs = np.nonzero(changed)
        maximum = float(delta.max())
        heat = np.round(np.clip(delta / maximum if maximum else delta, 0, 1) * 255).astype(np.uint8)
        Image.fromarray(heat).save(output / f'{record.stem}-difference.png')
        percentile = float(np.percentile(delta[changed], 99)) if len(xs) else 0.0
        detail = np.log1p(delta / percentile * 9) / np.log(10) if percentile else delta
        Image.fromarray(np.round(np.clip(detail, 0, 1) * 255).astype(np.uint8)).save(
            output / f'{record.stem}-difference-detail.png')
        Image.fromarray((changed * 255).astype(np.uint8)).save(output / f'{record.stem}-changed-mask.png')
        report = dict(data, payload_sha256=hashes, changed_pixels=int(changed.sum()),
                      rgb_changed_pixels=int(rgb_changed.sum()),
                      alpha_changed_pixels=int(alpha_changed.sum()) if fmt != 26 else None,
                      alpha_only_changed_pixels=int((alpha_changed & ~rgb_changed).sum()) if fmt != 26 else None,
                      changed_fraction=float(changed.mean()), invalid_pixels=int((~valid).sum()),
                      maximum_channel_delta=maximum,
                      changed_delta_p99=percentile,
                      difference_detail_note='Log contrast; white at the 99th percentile of changed-pixel channel deltas. Use numeric receipt for magnitude.',
                      changed_bbox_xyxy=[int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]
                      if len(xs) else None,
                      preview_note='R11 HDR uses Reinhard plus sRGB for display only; numeric differences use decoded values. RGBA differences include alpha.')
        reports.append(report)
    (output / 'analysis.json').write_text(json.dumps(reports, indent=2) + '\n', encoding='utf-8')
    return reports


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(json.dumps(analyze(args.source, args.output), indent=2))
