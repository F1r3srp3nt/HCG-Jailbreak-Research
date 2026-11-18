#!/usr/bin/env python3
"""The preset format's three descriptions agree: the JSON schema, the example
presets, and the C core's constants (HCGBackgroundCore.h / .c).

    python3 -I tests/test_schema.py

Standard library only: a small validator for the schema keywords the schema
uses (type, const, enum, required, minimum, maximum, exclusiveMinimum,
minLength, maxLength, pattern, $ref). Prints one summary line; exits 1 on any
mismatch.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT = os.path.join(ROOT, "HCGBackgroundKit")
SCHEMA = json.load(open(os.path.join(KIT, "Schema", "hcg-background-preset-v1.schema.json")))
CORE_H = open(os.path.join(KIT, "Sources", "HCGBackgroundKit", "include", "HCGBackgroundCore.h")).read()
CORE_C = open(os.path.join(KIT, "Sources", "HCGBackgroundKit", "HCGBackgroundCore.c")).read()
errors = []
checks = 0


def check(cond, message):
    global checks
    checks += 1
    if not cond:
        errors.append(message)


def resolve(node):
    ref = node.get("$ref")
    if ref:
        assert ref.startswith("#/$defs/")
        return SCHEMA["$defs"][ref.split("/")[-1]]
    return node


def validate(value, node, path="$"):
    node = resolve(node)
    problems = []
    t = node.get("type")
    types = {"object": dict, "string": str, "boolean": bool, "array": list}
    if t == "number":
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            return [f"{path}: expected number"]
    elif t in types and not isinstance(value, types[t]):
        return [f"{path}: expected {t}"]
    if "const" in node and value != node["const"]:
        problems.append(f"{path}: expected {node['const']!r}")
    if "enum" in node and value not in node["enum"]:
        problems.append(f"{path}: {value!r} not in {node['enum']}")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in node and value < node["minimum"]:
            problems.append(f"{path}: below minimum")
        if "maximum" in node and value > node["maximum"]:
            problems.append(f"{path}: above maximum")
        if "exclusiveMinimum" in node and value <= node["exclusiveMinimum"]:
            problems.append(f"{path}: not above {node['exclusiveMinimum']}")
    if isinstance(value, str):
        if "minLength" in node and len(value) < node["minLength"]:
            problems.append(f"{path}: too short")
        if "maxLength" in node and len(value) > node["maxLength"]:
            problems.append(f"{path}: too long")
        if "pattern" in node and not re.search(node["pattern"], value):
            problems.append(f"{path}: does not match {node['pattern']}")
    if isinstance(value, dict):
        for key in node.get("required", []):
            if key not in value:
                problems.append(f"{path}: missing {key}")
        for key, sub in node.get("properties", {}).items():
            if key in value:
                problems += validate(value[key], sub, f"{path}.{key}")
    return problems


def define(name, text=CORE_H):
    m = re.search(r"#define %s (\S+)" % name, text)
    return m.group(1).strip('"') if m else None


# Schema constants == C constants.
props = SCHEMA["properties"]
check(props["format"]["const"] == define("HCGBG_FORMAT_ID"), "format id differs from HCGBG_FORMAT_ID")
check(props["formatVersion"]["const"] == int(define("HCGBG_FORMAT_VERSION")), "formatVersion differs")
speed = props["playback"]["properties"]["speed"]
check(speed["minimum"] == float(define("HCGBG_SPEED_MIN")), "speed minimum differs")
check(speed["maximum"] == float(define("HCGBG_SPEED_MAX")), "speed maximum differs")
check(speed["default"] == float(define("HCGBG_SPEED_DEFAULT")), "speed default differs")
media = props["media"]["properties"]
check(media["width"]["minimum"] == int(define("HCGBG_MIN_DIMENSION")), "min dimension differs")
check(media["width"]["maximum"] == int(define("HCGBG_MAX_DIMENSION")), "max dimension differs")
check(media["duration"]["maximum"] == float(define("HCGBG_MAX_SOURCE_SECONDS")), "max duration differs")
crop = props["layout"]["properties"]["crop"]["properties"]
check(crop["width"]["minimum"] == float(define("HCGBG_CROP_MIN")), "crop minimum differs")
scaling_ids = re.findall(r'"(\w+)"', re.search(r"kScalingIds\[\] = \{([^}]*)\}", CORE_C).group(1))
check(props["layout"]["properties"]["scaling"]["enum"] == scaling_ids, f"scaling enum differs from {scaling_ids}")

# The file-name pattern refuses what HCGBackgroundPreset.isSafeFileName refuses.
pattern = SCHEMA["$defs"]["fileName"]["pattern"]
for bad in ["../x.mov", "a/b.mov", ".hidden", "x:y", "a\\b"]:
    check(not re.search(pattern, bad), f"file-name pattern accepts unsafe {bad!r}")
for good in ["media.mov", "6F0B-still.jpg", "Clip 1.mp4"]:
    check(re.search(pattern, good) is not None, f"file-name pattern refuses {good!r}")

# Every example validates, and its trim / still are inside the clip.
examples = []
for dirpath, _, files in os.walk(os.path.join(KIT, "Examples")):
    examples += [os.path.join(dirpath, f) for f in files if f == "preset.json"]
check(len(examples) >= 1, "no example presets")
for path in examples:
    doc = json.load(open(path))
    problems = validate(doc, SCHEMA)
    check(not problems, f"{os.path.relpath(path, ROOT)}: {problems}")
    pb = doc.get("playback", {})
    end = pb.get("trimEnd", 0) or doc["media"]["duration"]
    check(0 <= pb.get("trimStart", 0) < end <= doc["media"]["duration"], f"{path}: trim outside the clip")

# Documents the schema must refuse.
base = json.load(open(examples[0]))
for mutate, why in [
    (lambda d: d.update(formatVersion=2), "a newer major version"),
    (lambda d: d.update(format="other"), "another format"),
    (lambda d: d["media"].update(file="../../etc/passwd"), "a path outside the folder"),
    (lambda d: d["media"].update(duration=0), "zero duration"),
    (lambda d: d["playback"].update(speed=8), "speed out of range"),
    (lambda d: d["layout"].update(scaling="stretch"), "unknown scaling"),
    (lambda d: d.pop("media"), "no media"),
]:
    doc = json.loads(json.dumps(base))
    mutate(doc)
    check(validate(doc, SCHEMA), f"schema accepts {why}")

if errors:
    print("\n".join(errors))
    print(f"{len(errors)} of {checks} schema checks FAILED")
    sys.exit(1)
print(f"{checks} schema checks passed ({len(examples)} example preset{'s' if len(examples) != 1 else ''})")
