"""Read bounded SR resource metadata; never infer HUD pixels or GPU completion."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import sys

NAMES = ("Color", "Output", "Depth", "MotionVectors", "TransparencyMask",
         "ExposureTexture", "DLSS.Input.Bias.Current.Color.Mask")
HEADER = ("ngx_sr_probe=armed schema=1 runtime=32.0.16.1088 resource_get_slot=9 "
          "call_limit=32768 sample_limit=64 wait_for_stereo={gate} pixels_captured=0 publication=0")
TEMPORAL_HEADER = HEADER.replace("schema=1", "schema=2").replace(
    "call_limit=", "float_get_slot=14 integer_get_slot=11 unsigned_get_slot=12 call_limit=")
CONTEXT_HEADER = TEMPORAL_HEADER.replace("schema=2", "schema=3")
CREATION_HEADER = CONTEXT_HEADER.replace("schema=3", "schema=4")
STREAMLINE_HEADER = CREATION_HEADER.replace("schema=4", "schema=5")
STREAMLINE_FIELDS = {"call", "available", "sl_call", "viewport", "frame", "commands", "attribution_verified"}
CREATION_FLAG = "DLSS.Feature.Create.Flags"
CONTEXT_FIELDS = {"call", "phase", "available", "eye", "pose", "queued", "arms", "resets", "attribution_verified"}
SCALARS = {**dict.fromkeys(("Jitter.Offset.X", "Jitter.Offset.Y", "MV.Scale.X", "MV.Scale.Y",
                          "DLSS.Pre.Exposure"), "float"),
           **dict.fromkeys(("DLSS.Render.Subrect.Dimensions.Width",
                           "DLSS.Render.Subrect.Dimensions.Height"), "unsigned"), "Reset": "integer"}
SCALAR_FIELDS = {"call", "name", "type", "queried", "result", "valid", "value"}
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
    headers = {header.format(gate=gate): (gate == 1, version)
               for header, version in ((HEADER, 1), (TEMPORAL_HEADER, 2), (CONTEXT_HEADER, 3),
                                       (CREATION_HEADER, 4), (STREAMLINE_HEADER, 5)) for gate in (0, 1)}
    if not lines or lines[0] not in headers:
        raise ValueError("missing or unsupported SR header")
    gated, version = headers[lines[0]]
    scalar_types = {**SCALARS, **({CREATION_FLAG: "integer"} if version >= 4 else {})}
    calls = {}
    capture_context = None
    for line in lines[1:]:
        if not line.strip():
            continue
        kind, separator, rest = line.partition(" ")
        if not separator or kind not in ("NGX_SR_INPUT", "NGX_SR_EVAL", "NGX_SR_SCALAR", "NGX_SR_CONTEXT", "NGX_SR_STREAMLINE"):
            raise ValueError("unexpected SR record")
        data = fields(rest, INPUT_FIELDS if kind == "NGX_SR_INPUT" else
                      STREAMLINE_FIELDS if kind == "NGX_SR_STREAMLINE" else
                      CONTEXT_FIELDS if kind == "NGX_SR_CONTEXT" else
                      SCALAR_FIELDS if kind == "NGX_SR_SCALAR" else EVAL_FIELDS)
        call = number(data["call"])
        if not call or (kind in ("NGX_SR_INPUT", "NGX_SR_EVAL") and data["publication"] != "0"):
            raise ValueError("invalid call or publication claim")
        observation = calls.setdefault(call, {"call": call, "inputs": {}, "scalars": {}, "contexts": {}, "evaluation_result": None})
        if len(calls) > 64:
            raise ValueError("SR sample budget exceeded")
        if kind == "NGX_SR_STREAMLINE":
            if version < 5 or "streamline" in observation:
                raise ValueError("unsupported or duplicate Streamline context")
            if data["available"] not in ("0", "1") or data["attribution_verified"] != "0":
                raise ValueError("invalid Streamline context or attribution claim")
            context = {"available": data["available"] == "1",
                       "call": number(data["sl_call"]), "viewport": number(data["viewport"], 32),
                       "frame": number(data["frame"], hexadecimal=True),
                       "commands": number(data["commands"], hexadecimal=True)}
            if context["available"]:
                if not context["call"] or not context["frame"] or not context["commands"]:
                    raise ValueError("incomplete available Streamline context")
            elif any(context[name] for name in ("call", "viewport", "frame", "commands")):
                raise ValueError("unavailable Streamline context contains identity")
            observation["streamline"] = context
            continue
        elif kind == "NGX_SR_CONTEXT":
            phase = data["phase"]
            if version < 3 or phase not in ("before", "after") or phase in observation["contexts"]:
                raise ValueError("unsupported or duplicate context")
            if data["available"] not in ("0", "1") or data["attribution_verified"] != "0" or data["eye"] not in ("-1", "0", "1"):
                raise ValueError("invalid context flags or attribution claim")
            context = {name: number(data[name]) for name in ("pose", "queued", "arms", "resets")}
            context.update(available=data["available"] == "1", eye=int(data["eye"]))
            if (context["queued"] != 1 and (context["eye"] != -1 or context["pose"] != 0)) or (context["eye"] == -1 and context["pose"] != 0):
                raise ValueError("ambiguous queue must not report an eye or pose")
            if not context["available"] and (context["eye"] != -1 or any(context[name] for name in ("pose", "queued", "arms", "resets"))):
                raise ValueError("unavailable context contains values")
            observation["contexts"][phase] = context
            continue
        result = number(data["result"], 32, True)
        if kind == "NGX_SR_SCALAR":
            name = data["name"]
            if version < 2 or name not in scalar_types or data["type"] != scalar_types[name] or name in observation["scalars"]:
                raise ValueError("unsupported or duplicate scalar")
            if data["queried"] not in ("0", "1") or data["valid"] not in ("0", "1"):
                raise ValueError("invalid scalar flags")
            queried, valid = data["queried"] == "1", data["valid"] == "1"
            if (not queried and result != 0) or (valid and (not queried or result != 1)):
                raise ValueError("scalar contradicts query result")
            value = None
            if valid:
                value = float(data["value"])
                if not math.isfinite(value):
                    raise ValueError("nonfinite scalar")
                if data["type"] == "float" and abs(value) > 3.4028234663852886e38:
                    raise ValueError("scalar exceeds native float range")
                if data["type"] != "float":
                    if not re.fullmatch(r"-?[0-9]+", data["value"]):
                        raise ValueError("invalid integer scalar")
                    value = int(data["value"])
                    low, high = (0, 2**32) if data["type"] == "unsigned" else (-2**31, 2**31)
                    if not low <= value < high:
                        raise ValueError("scalar exceeds native range")
            elif data["value"] != "unavailable":
                raise ValueError("invalid scalar must not report a value")
            observation["scalars"][name] = {"type": data["type"], "queried": queried,
                                           "query_result": result, "valid": valid, "value": value}
            continue
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
    lifetime_flags = {}
    for call in sorted(calls):
        observation = calls[call]
        observation["missing_indexes"] = [i for i in range(7) if i not in observation["inputs"]]
        observation["missing_scalars"] = [name for name in scalar_types if name not in observation["scalars"]]
        creation = observation["scalars"].get(CREATION_FLAG)
        if creation and "identity" in observation:
            lifetime = observation["identity"]["lifetime"]
            if lifetime in lifetime_flags and lifetime_flags[lifetime] != creation:
                raise ValueError("creation flags changed within feature lifetime")
            lifetime_flags[lifetime] = creation
        observation["creation_flags"] = None
        if creation and creation["valid"]:
            bits = creation["value"] & 0xffffffff
            observation["creation_flags"] = {
                "source": "before_feature_creation", "bits": bits,
                "hdr": bool(bits & 1), "motion_vectors_low_resolution": bool(bits & 2),
                "motion_vectors_jittered": bool(bits & 4), "depth_inverted": bool(bits & 8),
                "sharpening": bool(bits & 32), "auto_exposure": bool(bits & 64),
                "alpha_upscaling": bool(bits & 128), "invalid_flag": bool(bits & 0x80000000),
                "uninterpreted_bits": bits & ~0x800000ef,
            }
        observation["scalar_records_complete"] = not observation["missing_scalars"]
        before, after = (observation["contexts"].get(phase) for phase in ("before", "after"))
        observation["context_records_complete"] = before is not None and after is not None
        streamline = observation.get("streamline")
        observation["streamline_context_record_present"] = streamline is not None
        observation["synchronous_streamline_command_match"] = bool(
            streamline and streamline["available"] and "identity" in observation and
            streamline["commands"] == observation["identity"]["commands"])
        observation["stable_pending_eye_tag"] = bool(before and after and before == after
            and before["available"] and before["queued"] == 1 and before["eye"] in (0, 1)
            and before["pose"] and before["arms"])
        observation["complete"] = (not observation["missing_indexes"] and
                                   observation["evaluation_result"] is not None)
        observation["evaluation_succeeded"] = (None if observation["evaluation_result"] is None
                                                 else observation["evaluation_result"] == 1)
        observation["inputs"] = [observation["inputs"][i] for i in sorted(observation["inputs"])]
        observations.append(observation)
    return {"schema": version, "metadata_only": True, "pixels_captured": False,
            "gpu_completion_verified": False, "hud_attribution_verified": False,
            "eye_attribution_verified": False,
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
