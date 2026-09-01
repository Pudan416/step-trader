#!/usr/bin/env python3
"""Render and verify the Day Objects Happening sample bank.

The renderer intentionally uses only the Python standard library. Its WAV writer
owns the byte layout so output does not vary with an installed audio utility.
"""

from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
import random
import re
import shutil
import struct
import subprocess
import sys
import wave
from pathlib import Path


PINNED_VCSL_REVISION = "c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e"
RENDERER_VERSION = "happening-bank-v1"
SAMPLE_RATE = 44_100
PEAK_AMPLITUDE = 10.0 ** (-3.0 / 20.0)
FADE_FRAMES = round(SAMPLE_RATE * 0.005)
MIN_DURATION_FRAMES = round(SAMPLE_RATE * 0.12)
MAX_DURATION_FRAMES = SAMPLE_RATE * 6

SCRIPT_DIR = Path(__file__).resolve().parent
REPOSITORY_ROOT = SCRIPT_DIR.parents[1]
SOURCE_MAP_PATH = SCRIPT_DIR / "happening-source-map.json"
DEFAULT_OUTPUT_ROOT = (
    REPOSITORY_ROOT
    / "StepsTrader/Experiments/DayObjects/Sound/Resources/Happenings"
)
MANIFEST_PATH = (
    REPOSITORY_ROOT
    / "StepsTrader/Experiments/DayObjects/Sound/Resources/audio-assets-manifest.json"
)
CATALOG_PATH = (
    REPOSITORY_ROOT
    / "StepsTrader/Experiments/DayObjects/Sound/Domain/HappeningSoundCatalog.swift"
)


class BuildError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_sha256(value: object) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return sha256_bytes(encoded)


def load_source_map() -> dict:
    with SOURCE_MAP_PATH.open("r", encoding="utf-8") as handle:
        source_map = json.load(handle)
    if source_map.get("schemaVersion") != 1:
        raise BuildError("happening-source-map.json schemaVersion must be 1")
    if source_map.get("rendererVersion") != RENDERER_VERSION:
        raise BuildError(f"rendererVersion must be {RENDERER_VERSION}")
    if source_map.get("vcslRevision") != PINNED_VCSL_REVISION:
        raise BuildError(f"VCSL revision must be {PINNED_VCSL_REVISION}")
    recipes = source_map.get("recipes", [])
    if [recipe.get("id") for recipe in recipes] != list(range(1, 31)):
        raise BuildError("source map must contain stable recipe IDs 1...30 in order")
    if sum(len(recipe.get("rootMIDIs", [])) for recipe in recipes) != 102:
        raise BuildError("source map must declare exactly 102 output roots")
    return source_map


def vcsl_input_path(checkout: Path, recipe: dict) -> Path:
    recorded_path = recipe["input"]["path"]
    annotation = f"{recipe['id']:02d} "
    if not recorded_path.startswith(annotation):
        raise BuildError(
            f"recipe {recipe['id']:02d} VCSL path must retain its leading recipe annotation"
        )
    return checkout / recorded_path.removeprefix(annotation)


def validate_vcsl_checkout(checkout: Path, source_map: dict) -> None:
    if shutil.which("git") is None:
        raise BuildError("git is required to validate the pinned VCSL checkout")
    if not (checkout / ".git").exists():
        raise BuildError(f"VCSL checkout is not a Git worktree: {checkout}")
    result = subprocess.run(
        ["git", "-C", str(checkout), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    revision = result.stdout.strip()
    if revision != PINNED_VCSL_REVISION:
        raise BuildError(
            f"VCSL checkout is at {revision}; expected {PINNED_VCSL_REVISION}. "
            f"Run: git -C {checkout} checkout {PINNED_VCSL_REVISION}"
        )
    for recipe in source_map["recipes"]:
        input_record = recipe.get("input")
        if input_record and not vcsl_input_path(checkout, recipe).is_file():
            raise BuildError(f"missing pinned VCSL input: {input_record['path']}")


def read_pcm_wav(path: Path) -> tuple[list[float], int]:
    try:
        with wave.open(str(path), "rb") as reader:
            channels = reader.getnchannels()
            sample_width = reader.getsampwidth()
            sample_rate = reader.getframerate()
            frame_count = reader.getnframes()
            compression = reader.getcomptype()
            payload = reader.readframes(frame_count)
    except (wave.Error, EOFError) as error:
        raise BuildError(f"unsupported WAV input {path}: {error}") from error
    if compression != "NONE":
        raise BuildError(f"compressed WAV input is unsupported: {path}")
    if channels < 1 or channels > 8:
        raise BuildError(f"unsupported channel count {channels}: {path}")
    if sample_width not in (1, 2, 3, 4):
        raise BuildError(f"unsupported PCM bit depth {sample_width * 8}: {path}")
    expected_bytes = frame_count * channels * sample_width
    if len(payload) != expected_bytes:
        raise BuildError(f"truncated PCM data in {path}")

    def decode_sample(offset: int) -> float:
        chunk = payload[offset : offset + sample_width]
        if sample_width == 1:
            return (chunk[0] - 128) / 128.0
        value = int.from_bytes(chunk, "little", signed=True)
        return value / float(1 << (sample_width * 8 - 1))

    mono: list[float] = []
    frame_width = channels * sample_width
    for frame_offset in range(0, len(payload), frame_width):
        total = 0.0
        for channel in range(channels):
            total += decode_sample(frame_offset + channel * sample_width)
        mono.append(total / channels)
    return mono, sample_rate


def resample_and_pitch(
    samples: list[float], source_rate: int, pitch_semitones: int
) -> list[float]:
    speed = 2.0 ** (pitch_semitones / 12.0)
    source_step = source_rate * speed / SAMPLE_RATE
    frame_count = min(int((len(samples) - 1) / source_step), MAX_DURATION_FRAMES)
    if frame_count < MIN_DURATION_FRAMES:
        raise BuildError(f"pitch transform produced only {frame_count} frames")
    output = [0.0] * frame_count
    for index in range(frame_count):
        source_position = index * source_step
        lower = int(source_position)
        fraction = source_position - lower
        output[index] = samples[lower] + (samples[lower + 1] - samples[lower]) * fraction
    return output


def midi_frequency(midi: int) -> float:
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))


def render_additive(recipe: dict, root_midi: int) -> list[float]:
    definition = recipe["definition"]
    count = round(definition["durationSeconds"] * SAMPLE_RATE)
    frequency = midi_frequency(root_midi)
    decay = definition["decay"]
    brightness = definition["brightness"]
    rng = random.Random(recipe["seed"] * 1000 + root_midi)
    phases = [rng.random() * math.tau for _ in range(5)]
    samples: list[float] = []
    for index in range(count):
        time = index / SAMPLE_RATE
        attack = min(1.0, time / 0.004)
        envelope = attack * math.exp(-decay * time)
        value = 0.0
        for harmonic in range(1, 6):
            amplitude = (brightness ** (harmonic - 1)) / harmonic
            value += amplitude * math.sin(math.tau * frequency * harmonic * time + phases[harmonic - 1])
        samples.append(value * envelope)
    return samples


def render_fm(recipe: dict, root_midi: int) -> list[float]:
    definition = recipe["definition"]
    count = round(definition["durationSeconds"] * SAMPLE_RATE)
    frequency = midi_frequency(root_midi)
    decay = definition["decay"]
    modulation_index = definition["modulationIndex"]
    phase = random.Random(recipe["seed"] * 1000 + root_midi).random() * math.tau
    samples: list[float] = []
    for index in range(count):
        time = index / SAMPLE_RATE
        attack = min(1.0, time / 0.010)
        envelope = attack * math.exp(-decay * time)
        modulator = math.sin(math.tau * frequency * 1.5 * time + phase)
        carrier = math.sin(math.tau * frequency * time + modulation_index * envelope * modulator)
        sub = math.sin(math.tau * frequency * 0.5 * time + phase * 0.5)
        samples.append((carrier * 0.78 + sub * 0.22) * envelope)
    return samples


def render_resonant_noise(recipe: dict) -> list[float]:
    definition = recipe["definition"]
    count = round(definition["durationSeconds"] * SAMPLE_RATE)
    decay = definition["decay"]
    rng = random.Random(recipe["seed"])
    frequencies = [midi_frequency(60 + pitch_class) for pitch_class in definition["resonatorPitchClasses"]]
    phases = [rng.random() * math.tau for _ in frequencies]
    filtered_noise = 0.0
    samples: list[float] = []
    for index in range(count):
        time = index / SAMPLE_RATE
        filtered_noise += 0.08 * (rng.uniform(-1.0, 1.0) - filtered_noise)
        resonators = sum(
            math.sin(math.tau * frequency * time + phase) / (tone + 1)
            for tone, (frequency, phase) in enumerate(zip(frequencies, phases))
        )
        envelope = min(1.0, time / 0.080) * math.exp(-decay * time)
        samples.append((0.30 * filtered_noise + 0.70 * resonators) * envelope)
    return samples


def render_texture_noise(recipe: dict) -> list[float]:
    definition = recipe["definition"]
    count = round(definition["durationSeconds"] * SAMPLE_RATE)
    coefficient = definition["lowpass"]
    pulse_rate = definition["pulseRateHz"]
    rng = random.Random(recipe["seed"])
    low = 0.0
    samples: list[float] = []
    for index in range(count):
        time = index / SAMPLE_RATE
        low += coefficient * (rng.uniform(-1.0, 1.0) - low)
        pulse = 0.55 + 0.45 * math.sin(math.tau * pulse_rate * time) ** 2
        envelope = min(1.0, time / 0.050) * min(1.0, (count - index) / (0.20 * SAMPLE_RATE))
        samples.append(low * pulse * envelope)
    return samples


def render_generated(recipe: dict, root_midi: int) -> list[float]:
    kind = recipe["definition"].get("kind")
    if kind == "additive-pluck":
        return render_additive(recipe, root_midi)
    if kind == "fm-soft":
        return render_fm(recipe, root_midi)
    if kind == "resonant-noise":
        return render_resonant_noise(recipe)
    if kind == "texture-noise":
        return render_texture_noise(recipe)
    raise BuildError(f"unknown generator kind: {kind}")


def trim_fade_normalize(samples: list[float]) -> list[int]:
    threshold = 10.0 ** (-60.0 / 20.0)
    first = next((index for index, value in enumerate(samples) if abs(value) >= threshold), None)
    last = next((index for index in range(len(samples) - 1, -1, -1) if abs(samples[index]) >= threshold), None)
    if first is None or last is None:
        raise BuildError("renderer produced silence")
    trimmed = samples[first : last + 1]
    if len(trimmed) < MIN_DURATION_FRAMES:
        raise BuildError(f"renderer produced only {len(trimmed)} non-silent frames")
    if len(trimmed) > MAX_DURATION_FRAMES:
        trimmed = trimmed[:MAX_DURATION_FRAMES]
    fade_count = min(FADE_FRAMES, len(trimmed) // 2)
    for index in range(fade_count):
        gain = index / fade_count
        trimmed[index] *= gain
        trimmed[-1 - index] *= gain
    peak = max(abs(value) for value in trimmed)
    if not math.isfinite(peak) or peak <= 0.0:
        raise BuildError("renderer produced an invalid peak")
    gain = PEAK_AMPLITUDE / peak
    pcm = [int(round(max(-1.0, min(1.0, value * gain)) * 32767.0)) for value in trimmed]
    if max(abs(value) for value in pcm) >= 32767:
        raise BuildError("normalization clipped the output")
    return pcm


def wav_bytes(pcm: list[int]) -> bytes:
    samples = array.array("h", pcm)
    if sys.byteorder != "little":
        samples.byteswap()
    payload = samples.tobytes()
    byte_rate = SAMPLE_RATE * 2
    header = (
        b"RIFF"
        + struct.pack("<I", 36 + len(payload))
        + b"WAVEfmt "
        + struct.pack("<IHHIIHH", 16, 1, 1, SAMPLE_RATE, byte_rate, 2, 16)
        + b"data"
        + struct.pack("<I", len(payload))
    )
    return header + payload


def output_name(recipe_id: int, root_midi: int) -> str:
    if recipe_id in (25, 26, 27):
        return "noise.wav"
    if recipe_id in (28, 29, 30):
        return "texture.wav"
    pitch_names = {0: "C", 3: "DSharp", 6: "FSharp", 9: "A"}
    pitch_class = root_midi % 12
    if pitch_class not in pitch_names:
        raise BuildError(f"unsupported production root MIDI {root_midi}")
    return f"{pitch_names[pitch_class]}{root_midi // 12 - 1}.wav"


def validate_wav_bytes(data: bytes, path: str) -> None:
    if len(data) < 44 or data[0:4] != b"RIFF" or data[8:16] != b"WAVEfmt ":
        raise BuildError(f"invalid deterministic WAV header: {path}")
    audio_format, channels, sample_rate = struct.unpack_from("<HHI", data, 20)
    bits = struct.unpack_from("<H", data, 34)[0]
    if (audio_format, channels, sample_rate, bits) != (1, 1, SAMPLE_RATE, 16):
        raise BuildError(f"wrong output WAV format: {path}")
    frames = (len(data) - 44) // 2
    if not MIN_DURATION_FRAMES <= frames <= MAX_DURATION_FRAMES:
        raise BuildError(f"output duration outside 0.12...6.0 seconds: {path}")


def render_bank(source_map: dict, checkout: Path, output_root: Path) -> dict[str, dict]:
    records: dict[str, dict] = {}
    for recipe in source_map["recipes"]:
        recipe_id = recipe["id"]
        input_record = recipe.get("input")
        source_samples: list[float] | None = None
        source_rate = SAMPLE_RATE
        if input_record:
            input_path = vcsl_input_path(checkout, recipe)
            input_record["sha256"] = sha256_file(input_path)
            source_samples, source_rate = read_pcm_wav(input_path)
            recipe.pop("definitionSha256", None)
        else:
            recipe["definitionSha256"] = canonical_sha256(recipe["definition"])
        outputs = []
        for root_midi in recipe["rootMIDIs"]:
            relative_path = f"Happenings/{recipe_id:02d}/{output_name(recipe_id, root_midi)}"
            if input_record:
                pitch_semitones = root_midi - input_record["rootMIDI"]
                assert source_samples is not None
                samples = resample_and_pitch(source_samples, source_rate, pitch_semitones)
            else:
                pitch_semitones = None
                samples = render_generated(recipe, root_midi)
            data = wav_bytes(trim_fade_normalize(samples))
            validate_wav_bytes(data, relative_path)
            destination = output_root / f"{recipe_id:02d}" / output_name(recipe_id, root_midi)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            output_record = {
                "path": relative_path,
                "rootMIDI": root_midi,
                "sha256": sha256_bytes(data),
            }
            if pitch_semitones is not None:
                output_record["pitchSemitones"] = pitch_semitones
            outputs.append(output_record)
            records[relative_path] = {
                "recipe": recipe,
                "output": output_record,
                "bytes": len(data),
            }
        recipe["outputs"] = outputs
    if len(records) != 102:
        raise BuildError(f"renderer emitted {len(records)} files instead of 102")
    return records


def write_source_map(source_map: dict) -> None:
    SOURCE_MAP_PATH.write_text(
        json.dumps(source_map, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def update_manifest(source_map: dict, records: dict[str, dict]) -> None:
    with MANIFEST_PATH.open("r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    manifest["sources"]["vcsl"] = {
        "creator": "Versilian Studios contributors",
        "licenseFilename": source_map["vcslLicenseFilename"],
        "licenseIdentifier": "CC0-1.0",
        "revision": source_map["vcslRevision"],
        "sourceURL": source_map["vcslSourceURL"],
    }
    manifest["sources"]["project-authored"] = {
        "creator": "Steps project",
        "licenseFilename": "",
        "licenseIdentifier": "Proprietary project asset",
        "rendererVersion": source_map["rendererVersion"],
        "revision": source_map["rendererVersion"],
        "sourceURL": "project://Scripts/day_objects_audio/happening-source-map.json",
    }
    assets = [asset for asset in manifest["assets"] if not asset["path"].startswith("Happenings/")]
    for path in sorted(records):
        record = records[path]
        recipe = record["recipe"]
        output = record["output"]
        input_record = recipe.get("input")
        if input_record:
            source_file = {"path": input_record["path"], "sha256": input_record["sha256"]}
            license_filename = source_map["vcslLicenseFilename"]
        else:
            source_file = {
                "path": f"Scripts/day_objects_audio/happening-source-map.json#recipe-{recipe['id']:02d}",
                "sha256": recipe["definitionSha256"],
            }
            license_filename = ""
        asset = {
            "conversion": {
                "bitDepth": 16,
                "channels": 1,
                "fadeMilliseconds": 5,
                "peakDBFS": -3.0,
                "sampleRateHz": SAMPLE_RATE,
                "tool": RENDERER_VERSION,
            },
            "licenseFilename": license_filename,
            "path": path,
            "rootMIDINote": output["rootMIDI"],
            "sha256": output["sha256"],
            "sourceFiles": [source_file],
            "sourceKey": recipe["sourceKey"],
        }
        if "pitchSemitones" in output:
            asset["offlinePitchTransformSemitones"] = output["pitchSemitones"]
        assets.append(asset)
    manifest["assets"] = assets
    MANIFEST_PATH.write_text(
        json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def update_catalog(records: dict[str, dict]) -> None:
    text = CATALOG_PATH.read_text(encoding="utf-8")
    entries = "\n".join(
        f'        "{path}": "{records[path]["output"]["sha256"]}",' for path in sorted(records)
    )
    replacement = f'''    private static let processedSHA256ByResourceName: [String: String] = [
{entries}
    ]

    private static func source(id: Int, index: Int, name: String, rootMIDI: UInt8) -> HappeningSampleSource {{
        let resourceName = "Happenings/\\(name)"
        guard let sha256 = processedSHA256ByResourceName[resourceName] else {{
            preconditionFailure("Missing processed SHA-256 for \\(resourceName)")
        }}
        return HappeningSampleSource(resourceName: resourceName, rootMIDI: rootMIDI, sha256: sha256)
    }}

'''
    pattern = re.compile(
        r"    (?:private static let processedSHA256ByResourceName:[\s\S]*?)?"
        r"private static func source\([\s\S]*?\n    }\n\n(?=    private static func makeID)",
    )
    updated, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise BuildError("could not locate HappeningSoundCatalog source hash block")
    CATALOG_PATH.write_text(updated, encoding="utf-8")


def verify_checked_output(source_map: dict, checkout: Path, output_root: Path) -> None:
    expected: dict[str, str] = {}
    for recipe in source_map["recipes"]:
        if recipe.get("input"):
            actual_input_hash = sha256_file(vcsl_input_path(checkout, recipe))
            if actual_input_hash != recipe["input"].get("sha256"):
                raise BuildError(f"stale original SHA-256 for recipe {recipe['id']:02d}")
        elif canonical_sha256(recipe["definition"]) != recipe.get("definitionSha256"):
            raise BuildError(f"stale generator definition SHA-256 for recipe {recipe['id']:02d}")
        for output in recipe.get("outputs", []):
            expected[output["path"]] = output["sha256"]
    if len(expected) != 102:
        raise BuildError(f"source map records {len(expected)} processed outputs instead of 102")

    actual_paths = sorted(path for path in output_root.rglob("*.wav") if path.is_file())
    if len(actual_paths) != 102:
        raise BuildError(f"output root contains {len(actual_paths)} WAVs instead of 102")
    for path in actual_paths:
        relative = "Happenings/" + path.relative_to(output_root).as_posix()
        data = path.read_bytes()
        validate_wav_bytes(data, relative)
        if expected.get(relative) != sha256_bytes(data):
            raise BuildError(f"processed SHA-256 mismatch: {relative}")

    with MANIFEST_PATH.open("r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    manifest_hashes = {
        asset["path"]: asset["sha256"]
        for asset in manifest["assets"]
        if asset["path"].startswith("Happenings/")
    }
    if manifest_hashes != expected:
        raise BuildError("audio asset manifest does not match source map processed hashes")
    catalog_text = CATALOG_PATH.read_text(encoding="utf-8")
    catalog_hashes = dict(re.findall(r'        "(Happenings/[^"]+)": "([0-9a-f]{64})",', catalog_text))
    if catalog_hashes != expected:
        raise BuildError("HappeningSoundCatalog does not match source map processed hashes")


def compare_temporary_render(source_map: dict, records: dict[str, dict]) -> None:
    expected = {
        output["path"]: output["sha256"]
        for recipe in source_map["recipes"]
        for output in recipe.get("outputs", [])
    }
    actual = {path: record["output"]["sha256"] for path, record in records.items()}
    if actual != expected:
        mismatches = sorted(path for path in set(actual) | set(expected) if actual.get(path) != expected.get(path))
        raise BuildError(f"temporary render differs from checked output: {mismatches[:5]}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vcsl-checkout", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--verify-only", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        source_map = load_source_map()
        checkout = args.vcsl_checkout.resolve()
        output_root = args.output_root.resolve()
        validate_vcsl_checkout(checkout, source_map)
        if args.verify_only:
            verify_checked_output(source_map, checkout, output_root)
            print(f"verified 102 deterministic WAVs at {output_root}")
            return 0
        records = render_bank(source_map, checkout, output_root)
        if output_root == DEFAULT_OUTPUT_ROOT.resolve():
            write_source_map(source_map)
            update_manifest(source_map, records)
            update_catalog(records)
            verify_checked_output(source_map, checkout, output_root)
        else:
            compare_temporary_render(load_source_map(), records)
        total_bytes = sum(record["bytes"] for record in records.values())
        print(f"rendered 102 deterministic WAVs ({total_bytes} bytes) at {output_root}")
        return 0
    except (BuildError, OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
