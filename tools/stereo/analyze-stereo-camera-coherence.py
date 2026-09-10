"""Compare paired camera metadata after removing known optical recentering."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import statistics


def vector(text, size=3):
    values = [float(value) for value in text.split(",")]
    if len(values) != size or not all(math.isfinite(value) for value in values):
        raise ValueError("invalid camera vector")
    return values


def transpose(matrix):
    return list(map(list, zip(*matrix)))


def multiply(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def optical(fov):
    left, right, up, down = fov
    if not (-math.pi / 2 < left < right < math.pi / 2 and
            -math.pi / 2 < down < up < math.pi / 2):
        raise ValueError("invalid eye frustum")
    yaw, pitch = -(left + right) / 2, (down + up) / 2
    c, s, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    return multiply([[c, -s, 0], [s, c, 0], [0, 0, 1]],
                    [[1, 0, 0], [0, cp, -sp], [0, sp, cp]])


def angle(a, b):
    norm = math.sqrt(sum(x*x for x in a) * sum(x*x for x in b))
    if norm < 1e-12:
        raise ValueError("degenerate camera direction or baseline")
    return math.degrees(math.acos(max(-1, min(1, sum(x*y for x, y in zip(a, b)) / norm))))


def measure(a, b, fovs, ipd):
    bases = [transpose([vector(row[name]) for name in
                       ("camera_right", "camera_fwd", "camera_up")]) for row in (a, b)]
    for basis in bases:
        product = multiply(transpose(basis), basis)
        determinant = sum(basis[0][i] * (basis[1][(i+1)%3] * basis[2][(i+2)%3] -
                                         basis[1][(i+2)%3] * basis[2][(i+1)%3]) for i in range(3))
        if max(abs(product[i][j] - int(i == j)) for i in range(3) for j in range(3)) > 0.001 or abs(determinant-1) > 0.001:
            raise ValueError("camera basis is not a proper orthonormal rotation")
    clean = [multiply(basis, transpose(optical(fov))) for basis, fov in zip(bases, fovs)]
    delta = [y-x for x, y in zip(vector(a["camera_pos"]), vector(b["camera_pos"]))]
    separation = math.sqrt(sum(x*x for x in delta))
    return {"raw_forward_degrees": angle(transpose(bases[0])[1], transpose(bases[1])[1]),
            "corrected_forward_degrees": angle(transpose(clean[0])[1], transpose(clean[1])[1]),
            "corrected_right_degrees": angle(transpose(clean[0])[0], transpose(clean[1])[0]),
            "corrected_up_degrees": angle(transpose(clean[0])[2], transpose(clean[1])[2]),
            "separation_metres": separation, "ipd_error_metres": abs(separation-ipd),
            "baseline_right_degrees": angle(delta, transpose(clean[0])[0])}


def analyze(consumer, constants, viewport_a, viewport_b, minimum_present=0):
    if viewport_a == viewport_b or min(viewport_a, viewport_b) < 0 or max(viewport_a, viewport_b) > 0xffffffff:
        raise ValueError("two distinct uint32 viewports are required")
    if "openxr.render_projection=recentered-symmetric" not in consumer.splitlines():
        raise ValueError("recentered symmetric projection is not established")
    fovs = []
    for eye in (0, 1):
        matches = re.findall(r"(?m)^openxr.runtime_fov.eye" + str(eye) + r"=([^\r\n]+)", consumer)
        if len(matches) != 1: raise ValueError("missing or ambiguous runtime frustum")
        fovs.append(vector(matches[0], 4))
    ipds = re.findall(r"(?m)^openxr.runtime_ipd_metres=([^\r\n]+)", consumer)
    if len(ipds) != 1: raise ValueError("missing or ambiguous runtime IPD")
    ipd = float(ipds[0])
    if not math.isfinite(ipd) or not 0 < ipd < 0.2: raise ValueError("invalid runtime IPD")
    groups = {}
    for line in constants.splitlines():
        if not line.startswith("SET_CONSTANTS\t"): continue
        row = {}
        for field in line.split("\t")[1:]:
            key, value = field.split("=", 1)
            if key in row: raise ValueError("duplicate constants field")
            row[key] = value
        viewport, present = int(row["viewport"]), int(row["present_frame"])
        if viewport not in (viewport_a, viewport_b) or present < minimum_present: continue
        if row["result"] != "0": continue
        key = present, int(row["frame_index"]), row["token"]
        groups.setdefault(key, {}).setdefault(viewport, []).append(row)
    pairs = [group for group in groups.values()
             if all(len(group.get(viewport, [])) == 1 for viewport in (viewport_a, viewport_b))]
    if not pairs: raise ValueError("no unambiguous matching frame pairs")
    candidates = []
    for left, right in ((viewport_a, viewport_b), (viewport_b, viewport_a)):
        rows = [measure(pair[left][0], pair[right][0], fovs, ipd) for pair in pairs]
        candidates.append({"assumed_eye0_viewport": left, "assumed_eye1_viewport": right,
                           "metrics": {name: {"min": min(values), "max": max(values),
                                              "median": statistics.median(values)}
                                       for name in rows[0]
                                       for values in [[row[name] for row in rows]]}})
    return {"matched_pairs": len(pairs), "excluded_groups": len(groups)-len(pairs),
            "minimum_present": minimum_present, "runtime_ipd_metres": ipd,
            "candidates": candidates, "physical_eye_attribution_verified": False,
            "pixels_validated": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("consumer", type=Path)
    parser.add_argument("constants", type=Path)
    parser.add_argument("--viewport-a", type=int, required=True)
    parser.add_argument("--viewport-b", type=int, required=True)
    parser.add_argument("--minimum-present", type=int, default=0)
    args = parser.parse_args()
    sources = [path.read_bytes() for path in (args.consumer, args.constants)]
    report = analyze(*(source.decode("utf-8-sig") for source in sources),
                     args.viewport_a, args.viewport_b, args.minimum_present)
    report["source_sha256"] = [hashlib.sha256(source).hexdigest() for source in sources]
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
