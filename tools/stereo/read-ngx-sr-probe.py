"""Read bounded SR resource metadata; never infer HUD pixels or GPU completion."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

NAMES = ("Color", "Output", "Depth", "MotionVectors", "TransparencyMask",
         "ExposureTexture", "DLSS.Input.Bias.Current.Color.Mask")
HEADER = ("ngx_sr_probe=armed schema=1 runtime=32.0.16.1088 resource_get_slot=9 "
          "call_limit=32768 sample_limit=64 wait_for_stereo={gate} pixels_captured=0 publication=0")
IDENTITY = ("feature", "lifetime", "commands", "thread", "batch", "present", "first_call")
DESCRIPTOR = ("dimension", "width", "height", "depth_or_array", "mips", "format", "samples")
INPUT_FIELDS = set(IDENTITY + DESCRIPTOR + ("call", "index", "name", "result", "resource",
                                          "described", "pixels_captured", "publication"))
EVAL_FIELDS = {"call", "result", "gpu_complete", "publication"}


def number(value, bits=64, hexadecimal=False):
    pattern = r"(?:0x)?[0-9a-fA-F]{1,16}" if hexadecimal else r"[0-9]{1,20}"
    if not re.fullmatch(pattern, value):
        raise ValueError("invalid numeric field")
    parsed = int(value, 16 if hexadecimal else 10)
    if parsed >= 1 << bits:
        raise ValueError("numeric field exceeds native range")
    return parsed


def fields(line, expected):
    result = {}
    for token in line.split():
        pair = token.split("=", 1)
        if len(pair) != 2 or pair[0] in result:
            raise ValueError("malformed or duplicate field")
        result[pair[0]] = pair[1]
    if result.keys() != expected:
        raise ValueError("missing or unsupported field")
    return result


def parse(text):
    lines = text.splitlines()
    if not lines or lines[0] not in (HEADER.format(gate=0), HEADER.format(gate=1)):
        raise ValueError("missing or unsupported SR header")
    gated = lines[0] == HEADER.format(gate=1)
    calls = {}
    capture_context = None
    for line in lines[1:]:
        if not line.strip():
            continue
        kind, separator, rest = line.partition(" ")
        if not separator or kind not in ("NGX_SR_INPUT", "NGX_SR_EVAL"):
            raise ValueError("unexpected SR record")
        data = fields(rest, INPUT_FIELDS if kind == "NGX_SR_INPUT" else EVAL_FIELDS)
        call = number(data["call"])
        if not call or data["publication"] != "0":
            raise ValueError("invalid call or publication claim")
        observation = calls.setdefault(call, {"call": call, "inputs": {}, "evaluation_result": None})
        if len(calls) > 64:
            raise ValueError("SR sample budget exceeded")
        result = number(data["result"], 32, True)
        if kind == "NGX_SR_EVAL":
            if data["gpu_complete"] != "0" or observation["evaluation_result"] is not None:
                raise ValueError("GPU completion claim or duplicate evaluation")
            observation["evaluation_result"] = result
            continue
        index = number(data["index"], 32)
        if index >= len(NAMES) or data["name"] != NAMES[index] or index in observation["inputs"]:
            raise ValueError("unknown, mismatched or duplicate resource index")
        identity = {name: number(data[name], 32 if name == "thread" else 64,
                                 name in ("feature", "commands")) for name in IDENTITY}
        if not identity["feature"] or not identity["lifetime"]:
            raise ValueError("unknown feature identity")
        if not 0 < call - identity["first_call"] <= 32768:
            raise ValueError("call outside capture window")
        context = tuple(identity[name] for name in ("batch", "present", "first_call"))
        if (gated and (not context[0] or not context[1])) or (not gated and context != (0, 0, 0)):
            raise ValueError("capture context disagrees with gate")
        if capture_context is not None and context != capture_context:
            raise ValueError("capture window changed within bounded probe")
        capture_context = context
        if "identity" in observation and observation["identity"] != identity:
            raise ValueError("resource identity changed within call")
        observation["identity"] = identity
        resource = number(data["resource"], hexadecimal=True)
        if data["described"] not in ("0", "1") or data["pixels_captured"] != "0":
            raise ValueError("invalid descriptor flag or pixel capture claim")
        described = data["described"] == "1"
        if described != (result == 1 and resource != 0):
            raise ValueError("descriptor contradicts query result")
        descriptor = {name: number(data[name], 64 if name == "width" else
                                   16 if name in ("depth_or_array", "mips") else 32)
                      for name in DESCRIPTOR}
        if not described and any(descriptor.values()):
            raise ValueError("descriptor present without successful resource")
        if described and (descriptor["dimension"] not in (1, 2, 3, 4) or
                          any(not descriptor[name] for name in
                              ("width", "height", "depth_or_array", "mips", "samples"))):
            raise ValueError("invalid resource descriptor")
        observation["inputs"][index] = {
            "index": index, "name": data["name"], "query_result": result,
            "resource": resource, "status": "described" if described else
            "query_failed" if result != 1 else "null_resource",
            "descriptor": descriptor if described else None,
        }
    observations = []
    for call in sorted(calls):
        observation = calls[call]
        observation["missing_indexes"] = [i for i in range(7) if i not in observation["inputs"]]
        observation["complete"] = (not observation["missing_indexes"] and
                                   observation["evaluation_result"] is not None)
        observation["evaluation_succeeded"] = (None if observation["evaluation_result"] is None
                                                 else observation["evaluation_result"] == 1)
        observation["inputs"] = [observation["inputs"][i] for i in sorted(observation["inputs"])]
        observations.append(observation)
    return {"schema": 1, "metadata_only": True, "pixels_captured": False,
            "gpu_completion_verified": False, "hud_attribution_verified": False,
            "wait_for_stereo": gated, "observed_calls": len(observations),
            "complete_calls": sum(item["complete"] for item in observations),
            "observations": observations}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    try:
        raw = args.path.read_bytes()
        report = parse(raw.decode("utf-8-sig"))
        report["source_sha256"] = hashlib.sha256(raw).hexdigest()
    except (OSError, UnicodeError, ValueError) as error:
        print(f"SR observation rejected: {error}", file=sys.stderr)
        return 2
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
