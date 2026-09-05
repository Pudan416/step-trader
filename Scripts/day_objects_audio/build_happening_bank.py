#!/usr/bin/env python3
"""Render and verify the Day Objects Happening sample bank.

The renderer intentionally uses only the Python standard library. Its WAV writer
owns the byte layout so output does not vary with an installed audio utility.
"""

from __future__ import annotations

import argparse
import array
import copy
import functools
import hashlib
import json
import math
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from Scripts.day_objects_audio import happening_audio_metrics as metrics
from Scripts.day_objects_audio import happening_synthesis as synthesis


PINNED_VCSL_REVISION = "c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e"
RENDERER_VERSION = "happening-bank-v3"
SAMPLE_RATE = 44_100
FADE_FRAMES = round(SAMPLE_RATE * 0.005)
MIN_DURATION_FRAMES = round(SAMPLE_RATE * 0.12)
MAX_DURATION_FRAMES = synthesis.MAX_RENDER_FRAMES
TAIL_TAPER_FRAMES = SAMPLE_RATE
TAIL_BOUNDARY_RMS_DBFS = -45.0
RESAMPLER_TAPS = 32
RESAMPLER_PHASES = 1024
RESAMPLER_WINDOW = "blackman"
MASTERING_TARGETS = {
    "tonal-organic": metrics.MasteringTarget(-22.0, -18.0),
    "texture": metrics.MasteringTarget(-26.0, -21.0),
}

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
SOURCES_PATH = (
    REPOSITORY_ROOT
    / "StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses/SOURCES.json"
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


def renderer_implementation_sha256() -> str:
    return sha256_file(Path(__file__).resolve())


def require(condition: bool, message: str) -> None:
    if not condition:
        raise BuildError(message)


def require_sha256(value: object, field: str) -> None:
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None,
            f"{field} must be a lowercase SHA-256")


def expected_render_format() -> dict:
    return {
        "sampleRateHz": SAMPLE_RATE,
        "channels": 1,
        "bitDepth": 16,
        "peakDBFS": -6.0,
        "fadeMilliseconds": 5,
        "maximumDurationSeconds": synthesis.MAX_RENDER_SECONDS,
        "tailTaperMilliseconds": 1000,
        "tailBoundaryRMSDBFS": TAIL_BOUNDARY_RMS_DBFS,
        "onsetRMSDBFS": -15.0,
        "dcCeilingDBFS": metrics.DC_CEILING_DBFS,
        "maximumGainDB": 12.0,
        "masteringTargets": {
            "tonal-organic": {"rmsMinDBFS": -22.0, "rmsMaxDBFS": -18.0},
            "texture": {"rmsMinDBFS": -26.0, "rmsMaxDBFS": -21.0},
        },
        "resampler": {
            "algorithm": "windowed-sinc-bandlimited",
            "taps": RESAMPLER_TAPS,
            "phases": RESAMPLER_PHASES,
            "window": RESAMPLER_WINDOW,
            "coefficientDecimalPlaces": 15,
        },
    }


def render_identity_for_recipe(recipe: dict, source_map: dict) -> str:
    identity = {
        "rendererVersion": source_map.get("rendererVersion"),
        "rendererImplementationSha256": source_map.get("rendererImplementationSha256"),
        "renderFormat": source_map.get("renderFormat"),
        "recipe": {
            "id": recipe.get("id"),
            "workingName": recipe.get("workingName"),
            "paletteKind": recipe.get("paletteKind"),
            "topology": recipe.get("topology"),
            "attackTopology": recipe.get("attackTopology"),
            "tailTopology": recipe.get("tailTopology"),
            "masteringFamily": recipe.get("masteringFamily"),
            "tail": recipe.get("tail"),
            "sourceKey": recipe.get("sourceKey"),
            "seed": recipe.get("seed"),
            "rootMIDIs": recipe.get("rootMIDIs"),
            "definition": recipe.get("definition"),
            "input": recipe.get("input"),
        },
    }
    return canonical_sha256(identity)


def validate_source_map(source_map: object, *, allow_stale_derived: bool = False) -> None:
    require(isinstance(source_map, dict), "source map root must be an object")
    require(source_map.get("schemaVersion") == 1, "source map schemaVersion must be 1")
    require(isinstance(source_map.get("rendererVersion"), str), "rendererVersion must be a string")
    require(source_map.get("vcslRevision") == PINNED_VCSL_REVISION,
            f"VCSL revision must be {PINNED_VCSL_REVISION}")
    require(isinstance(source_map.get("vcslSourceURL"), str), "vcslSourceURL must be a string")
    require(isinstance(source_map.get("vcslLicenseFilename"), str),
            "vcslLicenseFilename must be a string")
    render_format = source_map.get("renderFormat")
    require(isinstance(render_format, dict), "renderFormat must be an object")
    if not allow_stale_derived:
        require(render_format == expected_render_format(), "renderFormat does not match renderer parameters")
    recipes = source_map.get("recipes")
    require(isinstance(recipes, list), "recipes must be an array")
    require(len(recipes) == 30, "source map must contain 30 recipes")
    ids: list[int] = []
    palette_counts = {"synth": 0, "organic": 0, "hybrid": 0}
    topologies: list[str] = []
    attack_tail_pairs: set[tuple[str, str]] = set()
    vcsl_ids: set[int] = set()
    output_count = 0
    for index, recipe in enumerate(recipes):
        label = f"recipes[{index}]"
        require(isinstance(recipe, dict), f"{label} must be an object")
        recipe_id = recipe.get("id")
        require(isinstance(recipe_id, int) and not isinstance(recipe_id, bool), f"{label}.id must be an integer")
        ids.append(recipe_id)
        for field in ("workingName", "topology", "attackTopology", "tailTopology"):
            require(isinstance(recipe.get(field), str) and bool(recipe[field].strip()),
                    f"{label}.{field} must be a non-empty string")
        palette = recipe.get("paletteKind")
        require(palette in palette_counts, f"{label}.paletteKind is invalid")
        palette_counts[palette] += 1
        topology = recipe["topology"]
        topologies.append(topology)
        pair = (recipe["attackTopology"], recipe["tailTopology"])
        require(pair not in attack_tail_pairs, f"{label} duplicates attack/tail topology pair {pair}")
        attack_tail_pairs.add(pair)
        mastering_family = recipe.get("masteringFamily")
        expected_family = "tonal-organic" if recipe_id <= 24 else "texture"
        require(mastering_family == expected_family,
                f"{label}.masteringFamily must be {expected_family}")
        tail = recipe.get("tail")
        require(isinstance(tail, dict), f"{label}.tail must be an object")
        require(tail.get("kind") == recipe["tailTopology"],
                f"{label}.tail.kind must match tailTopology")
        require(isinstance(tail.get("durationSeconds"), (int, float))
                and not isinstance(tail.get("durationSeconds"), bool)
                and 0.0 < float(tail["durationSeconds"]) <= synthesis.MAX_RENDER_SECONDS,
                f"{label}.tail.durationSeconds is invalid")
        require(recipe.get("sourceKey") in ("vcsl", "project-authored"),
                f"{label}.sourceKey is invalid")
        if recipe["sourceKey"] == "vcsl":
            vcsl_ids.add(recipe_id)
        require(isinstance(recipe.get("seed"), int) and not isinstance(recipe.get("seed"), bool),
                f"{label}.seed must be an integer")
        roots = recipe.get("rootMIDIs")
        require(isinstance(roots, list) and roots and all(isinstance(root, int) for root in roots),
                f"{label}.rootMIDIs must be a non-empty integer array")
        require(len(roots) == (4 if recipe_id <= 24 else 1),
                f"{label}.rootMIDIs must contain {'four roots' if recipe_id <= 24 else 'one root'}")
        if recipe_id <= 24:
            require({root % 12 for root in roots} == {0, 3, 6, 9},
                    f"{label}.rootMIDIs must use C/D-sharp/F-sharp/A pitch classes")
        output_count += len(roots)
        input_record = recipe.get("input")
        definition = recipe.get("definition")
        require((input_record is None) != (definition is None),
                f"{label} must have exactly one of input or definition")
        if input_record is not None:
            require(isinstance(input_record, dict), f"{label}.input must be an object")
            require(isinstance(input_record.get("path"), str), f"{label}.input.path must be a string")
            require(isinstance(input_record.get("rootMIDI"), int), f"{label}.input.rootMIDI must be an integer")
            require_sha256(input_record.get("sha256"), f"{label}.input.sha256")
            require(isinstance(input_record.get("processingGainDB"), (int, float))
                    and not isinstance(input_record.get("processingGainDB"), bool)
                    and 0.0 <= float(input_record["processingGainDB"]) <= 36.0,
                    f"{label}.input.processingGainDB must be within 0...36 dB")
        else:
            require(isinstance(definition, dict) and isinstance(definition.get("kind"), str),
                    f"{label}.definition must be an object with a kind")
            require(definition.get("id") == recipe_id, f"{label}.definition.id must match id")
            require(definition.get("kind") == topology, f"{label}.definition.kind must match topology")
            require(definition.get("attackTopology") == recipe["attackTopology"],
                    f"{label}.definition.attackTopology must match attackTopology")
            require(definition.get("tail") == tail, f"{label}.definition.tail must match tail")
            if not allow_stale_derived:
                require_sha256(recipe.get("definitionSha256"), f"{label}.definitionSha256")
        outputs = recipe.get("outputs")
        require(isinstance(outputs, list) and len(outputs) == len(roots),
                f"{label}.outputs must match rootMIDIs")
        for output_index, output in enumerate(outputs):
            require(isinstance(output, dict), f"{label}.outputs[{output_index}] must be an object")
            require(isinstance(output.get("path"), str), f"{label}.outputs[{output_index}].path must be a string")
            require(isinstance(output.get("rootMIDI"), int), f"{label}.outputs[{output_index}].rootMIDI must be an integer")
            require(output.get("rootMIDI") == roots[output_index],
                    f"{label}.outputs[{output_index}].rootMIDI must match rootMIDIs")
            require_sha256(output.get("sha256"), f"{label}.outputs[{output_index}].sha256")
        if not allow_stale_derived:
            require_sha256(recipe.get("renderIdentitySha256"), f"{label}.renderIdentitySha256")
    require(ids == list(range(1, 31)), "source map must contain stable recipe IDs 1...30 in order")
    require(palette_counts == {"synth": 10, "organic": 10, "hybrid": 10},
            "source map must contain ten recipes per palette kind")
    require(len(set(topologies)) >= 12, "source map must contain at least twelve topologies")
    require(all(not (topologies[index] == topologies[index + 1] == topologies[index + 2])
                for index in range(len(topologies) - 2)),
            "source map may not contain three adjacent equal topologies")
    require(vcsl_ids == {9, 10, 11, 17, 18},
            "only recipes 09, 10, 11, 17, and 18 may use VCSL")
    require(output_count == 102, "source map must declare exactly 102 output roots")


def validate_render_identities(source_map: dict) -> None:
    require(source_map.get("rendererVersion") == RENDERER_VERSION,
            f"rendererVersion must be {RENDERER_VERSION}; render identity is stale")
    actual_implementation = renderer_implementation_sha256()
    require(source_map.get("rendererImplementationSha256") == actual_implementation,
            "renderer implementation SHA-256 does not match; render identity is stale")
    require(source_map.get("renderFormat") == expected_render_format(),
            "renderer parameters do not match; render identity is stale")
    for recipe in source_map["recipes"]:
        expected = render_identity_for_recipe(recipe, source_map)
        require(recipe.get("renderIdentitySha256") == expected,
                f"recipe {recipe['id']:02d} render identity is stale")


def load_source_map() -> dict:
    with SOURCE_MAP_PATH.open("r", encoding="utf-8") as handle:
        source_map = json.load(handle)
    validate_source_map(source_map)
    validate_render_identities(source_map)
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
        if input_record:
            input_path = vcsl_input_path(checkout, recipe)
            if not input_path.is_file():
                raise BuildError(f"missing pinned VCSL input: {input_record['path']}")
            actual_hash = sha256_file(input_path)
            if actual_hash != input_record["sha256"]:
                raise BuildError(
                    f"dirty or non-committed pinned VCSL input has wrong SHA-256: "
                    f"{input_record['path']} (expected {input_record['sha256']}, got {actual_hash})"
                )


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
    frame_count = int(len(samples) / source_step)
    if frame_count < MIN_DURATION_FRAMES:
        raise BuildError(f"pitch transform produced only {frame_count} frames")
    coefficient_table = resampler_coefficient_table(round(source_step, 15))
    half = RESAMPLER_TAPS // 2
    output: list[float] = []
    for index in range(frame_count):
        source_position = index * source_step
        center = math.floor(source_position)
        fraction = source_position - center
        phase = min(RESAMPLER_PHASES - 1, int(fraction * RESAMPLER_PHASES))
        coefficients = coefficient_table[phase]
        start = center - half + 1
        value = 0.0
        for tap, coefficient in enumerate(coefficients):
            source_index = start + tap
            if 0 <= source_index < len(samples):
                value += samples[source_index] * coefficient
        output.append(value)
    return output


@functools.lru_cache(maxsize=64)
def resampler_coefficient_table(source_step: float) -> tuple[tuple[float, ...], ...]:
    """Return a quantized-phase Blackman windowed-sinc low-pass kernel.

    The cutoff follows the source traversal rate, so upward pitch shifts remove
    content above the reduced Nyquist limit before decimation.
    """
    cutoff = min(1.0, 1.0 / source_step)
    half = RESAMPLER_TAPS // 2
    phases: list[tuple[float, ...]] = []
    for phase_index in range(RESAMPLER_PHASES):
        fraction = phase_index / RESAMPLER_PHASES
        coefficients: list[float] = []
        for tap in range(RESAMPLER_TAPS):
            distance = (tap - half + 1) - fraction
            argument = cutoff * distance
            sinc = 1.0 if argument == 0.0 else math.sin(math.pi * argument) / (math.pi * argument)
            window_position = (tap + 0.5) / RESAMPLER_TAPS
            window = 0.42 - 0.5 * math.cos(math.tau * window_position) + 0.08 * math.cos(2.0 * math.tau * window_position)
            coefficients.append(cutoff * sinc * window)
        total = sum(coefficients)
        phases.append(tuple(round(value / total, 15) for value in coefficients))
    return tuple(phases)


def render_generated(recipe: dict, root_midi: int) -> synthesis.RenderedEvent:
    return synthesis.render_authored(
        recipe["definition"], root_midi=root_midi, seed=recipe["seed"]
    )


def _audible_samples(samples: list[float]) -> list[float]:
    first = next(
        (index for index, value in enumerate(samples) if abs(value) >= metrics.AUDIBLE_THRESHOLD),
        None,
    )
    if first is None:
        raise BuildError("recorded source contains no audible samples")
    last = next(
        index for index in range(len(samples) - 1, -1, -1)
        if abs(samples[index]) >= metrics.AUDIBLE_THRESHOLD
    )
    return samples[first : last + 1]


def render_recorded(recipe: dict, samples: list[float], root_midi: int) -> synthesis.RenderedEvent:
    settings = {
        "vcsl-marimba-dark": (0.62, 2_600.0, 0.30, 0.012, 1),
        "vcsl-balafon-dry": (0.54, 3_900.0, 0.22, 0.006, 1),
        "vcsl-vibe-chorus": (0.70, 3_000.0, 0.38, 0.020, 1),
        "vcsl-tubular-dark": (0.86, 3_100.0, 0.48, 0.035, 2),
        "vcsl-chime-dark": (0.92, 2_600.0, 0.56, 0.060, 2),
    }
    topology = recipe["topology"]
    if topology not in settings:
        raise BuildError(f"unknown recorded topology: {topology}")
    duration, cutoff, decay, attack, lowpass_passes = settings[topology]
    body = _audible_samples(samples)[: round(duration * SAMPLE_RATE)]
    input_gain = 10.0 ** (float(recipe["input"]["processingGainDB"]) / 20.0)
    body = [sample * input_gain for sample in body]
    envelope = synthesis.exponential_envelope(len(body), decay, attack)
    body = [sample * amount for sample, amount in zip(body, envelope)]
    for _ in range(lowpass_passes):
        body = synthesis.one_pole_lowpass(body, cutoff)
    rendered = synthesis.apply_rendered_tail(
        body, root_midi=root_midi, tail=recipe["tail"], seed=recipe["seed"]
    )
    if topology in {"vcsl-tubular-dark", "vcsl-chime-dark"}:
        final_lowpass_passes = 2 if topology == "vcsl-tubular-dark" else 8
        for _ in range(final_lowpass_passes):
            rendered = synthesis.one_pole_lowpass(rendered, 2_200.0)
        if topology == "vcsl-chime-dark":
            rendered = [sample * (10.0 ** (1.5 / 20.0)) for sample in rendered]
    return synthesis.RenderedEvent(
        samples=rendered,
        topology=topology,
        attack_topology=recipe["attackTopology"],
        tail_topology=recipe["tailTopology"],
    )


def mastering_target(recipe: dict) -> metrics.MasteringTarget:
    family = recipe.get("masteringFamily")
    if family not in MASTERING_TARGETS:
        raise BuildError(f"unknown mastering family: {family}")
    return MASTERING_TARGETS[family]


def _level_snapshot(samples: list[float]) -> tuple[float, float, float]:
    audible = [sample for sample in samples if abs(sample) >= metrics.AUDIBLE_THRESHOLD]
    if not audible:
        raise BuildError("renderer produced silence")
    first = next(index for index, sample in enumerate(samples)
                 if abs(sample) >= metrics.AUDIBLE_THRESHOLD)
    onset = samples[first : first + round(SAMPLE_RATE * metrics.ONSET_SECONDS)]
    return (
        metrics.amplitude_to_dbfs(max(abs(sample) for sample in samples)),
        metrics.amplitude_to_dbfs(metrics.rms(audible)),
        metrics.amplitude_to_dbfs(metrics.rms(onset)),
    )


def prepare_for_mastering(
    samples: list[float], target: metrics.MasteringTarget
) -> list[float]:
    """Condition crest and onset ratios that scalar mastering cannot repair."""
    prepared = list(samples)
    if not prepared or len(prepared) > MAX_DURATION_FRAMES:
        raise BuildError("rendered event has an invalid frame count")
    margin_db = 0.30
    for _ in range(8):
        peak_dbfs, rms_dbfs, onset_dbfs = _level_snapshot(prepared)
        required_gain_db = target.rms_min_dbfs - rms_dbfs
        peak_allowance_db = target.peak_ceiling_dbfs - peak_dbfs
        onset_allowance_db = target.onset_ceiling_dbfs - onset_dbfs
        if (
            peak_allowance_db >= required_gain_db + margin_db
            and onset_allowance_db >= required_gain_db
            and target.maximum_gain_db >= required_gain_db
        ):
            # Freeze the audible set before scalar mastering. Without this
            # deterministic floor, bounded gain can pull a long sub-threshold
            # recorded tail above -60 dBFS and lower the measured result after
            # the gain was chosen from the pre-master audible set.
            return [
                sample if abs(sample) >= metrics.AUDIBLE_THRESHOLD else 0.0
                for sample in prepared
            ]

        if peak_allowance_db < required_gain_db + margin_db:
            maximum_peak_dbfs = target.peak_ceiling_dbfs - required_gain_db - margin_db
            ceiling = 10.0 ** (maximum_peak_dbfs / 20.0)
            prepared = [ceiling * math.tanh(sample / ceiling) for sample in prepared]

        peak_dbfs, rms_dbfs, onset_dbfs = _level_snapshot(prepared)
        required_gain_db = target.rms_min_dbfs - rms_dbfs
        onset_allowance_db = target.onset_ceiling_dbfs - onset_dbfs
        if onset_allowance_db < required_gain_db:
            attenuation_db = required_gain_db - onset_allowance_db + margin_db
            onset_gain = 10.0 ** (-attenuation_db / 20.0)
            first = next(index for index, sample in enumerate(prepared)
                         if abs(sample) >= metrics.AUDIBLE_THRESHOLD)
            onset_frames = round(SAMPLE_RATE * metrics.ONSET_SECONDS)
            transition_frames = round(SAMPLE_RATE * 0.015)
            for index in range(first, min(len(prepared), first + onset_frames + transition_frames)):
                relative = index - first
                if relative < onset_frames:
                    gain = onset_gain
                else:
                    progress = (relative - onset_frames) / max(transition_frames - 1, 1)
                    gain = onset_gain + (1.0 - onset_gain) * progress
                prepared[index] *= gain
    raise BuildError("rendered event cannot be conditioned for bounded mastering")


def trim_fade_master(samples: list[float], target: metrics.MasteringTarget) -> list[int]:
    if len(samples) > MAX_DURATION_FRAMES:
        raise BuildError(
            f"renderer produced {len(samples)} frames; maximum is {MAX_DURATION_FRAMES}"
        )
    mastered = metrics.master_event(samples, target=target, sample_rate=SAMPLE_RATE)
    if len(mastered) < MIN_DURATION_FRAMES:
        raise BuildError(f"renderer produced only {len(mastered)} non-silent frames")
    return [
        int(round(max(-1.0, min(1.0, sample)) * 32767.0))
        for sample in mastered
    ]


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
        raise BuildError(
            f"output duration outside 0.12...{synthesis.MAX_RENDER_SECONDS:.1f} seconds: {path}"
        )


def render_bank(source_map: dict, checkout: Path, output_root: Path) -> dict[str, dict]:
    records: dict[str, dict] = {}
    for recipe in source_map["recipes"]:
        recipe_id = recipe["id"]
        input_record = recipe.get("input")
        source_samples: list[float] | None = None
        source_rate = SAMPLE_RATE
        if input_record:
            input_path = vcsl_input_path(checkout, recipe)
            source_samples, source_rate = read_pcm_wav(input_path)
        else:
            recipe["definitionSha256"] = canonical_sha256(recipe["definition"])
        recipe["renderIdentitySha256"] = render_identity_for_recipe(recipe, source_map)
        outputs = []
        for root_midi in recipe["rootMIDIs"]:
            relative_path = f"Happenings/{recipe_id:02d}/{output_name(recipe_id, root_midi)}"
            if input_record:
                pitch_semitones = root_midi - input_record["rootMIDI"]
                assert source_samples is not None
                pitched = resample_and_pitch(source_samples, source_rate, pitch_semitones)
                rendered = render_recorded(recipe, pitched, root_midi)
            else:
                pitch_semitones = None
                rendered = render_generated(recipe, root_midi)
            require(rendered.topology == recipe["topology"],
                    f"recipe {recipe_id:02d} rendered unexpected topology {rendered.topology}")
            require(rendered.attack_topology == recipe["attackTopology"],
                    f"recipe {recipe_id:02d} rendered unexpected attack topology")
            require(rendered.tail_topology == recipe["tailTopology"],
                    f"recipe {recipe_id:02d} rendered unexpected tail topology")
            target = mastering_target(recipe)
            prepared = prepare_for_mastering(rendered.samples, target)
            data = wav_bytes(trim_fade_master(prepared, target))
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
        assets.append(expected_asset_record(source_map, record["recipe"], record["output"]))
    manifest["assets"] = assets
    MANIFEST_PATH.write_text(
        json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def update_sources(source_map: dict) -> None:
    with SOURCES_PATH.open("r", encoding="utf-8") as handle:
        sources = json.load(handle)
    vcsl_record = {
        "project": "VCSL",
        "sourceURL": source_map["vcslSourceURL"],
        "revision": source_map["vcslRevision"],
        "licenseFilename": source_map["vcslLicenseFilename"],
        "selectedPaths": [
            recipe["input"]["path"]
            for recipe in source_map["recipes"]
            if recipe.get("input")
        ],
    }
    updated = [item for item in sources if item.get("project") != "VCSL"]
    updated.append(vcsl_record)
    SOURCES_PATH.write_text(
        json.dumps(updated, indent=2, ensure_ascii=False) + "\n",
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


def expected_processed_hashes(source_map: dict) -> dict[str, str]:
    expected = {
        output["path"]: output["sha256"]
        for recipe in source_map["recipes"]
        for output in recipe["outputs"]
    }
    require(len(expected) == 102, f"source map records {len(expected)} processed outputs instead of 102")
    return expected


def expected_asset_record(source_map: dict, recipe: dict, output: dict) -> dict:
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
        "conversion": {**source_map["renderFormat"], "tool": source_map["rendererVersion"]},
        "licenseFilename": license_filename,
        "path": output["path"],
        "renderIdentitySha256": recipe["renderIdentitySha256"],
        "rootMIDINote": output["rootMIDI"],
        "sha256": output["sha256"],
        "sourceFiles": [source_file],
        "sourceKey": recipe["sourceKey"],
    }
    if "pitchSemitones" in output:
        asset["offlinePitchTransformSemitones"] = output["pitchSemitones"]
    return asset


def validate_complete_metadata(source_map: dict, manifest: object, sources: object) -> None:
    require(isinstance(manifest, dict), "audio asset manifest root must be an object")
    manifest_sources = manifest.get("sources")
    require(isinstance(manifest_sources, dict), "audio asset manifest sources must be an object")
    expected_vcsl_source = {
        "creator": "Versilian Studios contributors",
        "licenseFilename": source_map["vcslLicenseFilename"],
        "licenseIdentifier": "CC0-1.0",
        "revision": source_map["vcslRevision"],
        "sourceURL": source_map["vcslSourceURL"],
    }
    expected_project_source = {
        "creator": "Steps project",
        "licenseFilename": "",
        "licenseIdentifier": "Proprietary project asset",
        "rendererVersion": source_map["rendererVersion"],
        "revision": source_map["rendererVersion"],
        "sourceURL": "project://Scripts/day_objects_audio/happening-source-map.json",
    }
    require(manifest_sources.get("vcsl") == expected_vcsl_source,
            "audio asset manifest VCSL provenance diverges from source map")
    require(manifest_sources.get("project-authored") == expected_project_source,
            "audio asset manifest renderer provenance diverges from source map")
    assets = manifest.get("assets")
    require(isinstance(assets, list), "audio asset manifest assets must be an array")
    actual_assets = {
        asset.get("path"): asset for asset in assets
        if isinstance(asset, dict) and isinstance(asset.get("path"), str)
        and asset["path"].startswith("Happenings/")
    }
    expected_assets = {
        output["path"]: expected_asset_record(source_map, recipe, output)
        for recipe in source_map["recipes"] for output in recipe["outputs"]
    }
    require(actual_assets == expected_assets,
            "complete Happening asset metadata diverges from canonical source map records")
    require(isinstance(sources, list), "SOURCES.json root must be an array")
    vcsl_records = [item for item in sources if isinstance(item, dict) and item.get("project") == "VCSL"]
    require(len(vcsl_records) == 1, "SOURCES.json must contain exactly one VCSL record")
    expected_selected_paths = [
        recipe["input"]["path"] for recipe in source_map["recipes"] if recipe.get("input")
    ]
    expected_sources_record = {
        "project": "VCSL",
        "sourceURL": source_map["vcslSourceURL"],
        "revision": source_map["vcslRevision"],
        "licenseFilename": source_map["vcslLicenseFilename"],
        "selectedPaths": expected_selected_paths,
    }
    require(vcsl_records[0] == expected_sources_record,
            "SOURCES.json VCSL provenance diverges from source map")


def validate_output_inventory(output_root: Path, expected: dict[str, str]) -> None:
    actual_files = sorted(path for path in output_root.rglob("*") if path.is_file())
    actual_relative = {"Happenings/" + path.relative_to(output_root).as_posix(): path for path in actual_files}
    unexpected = sorted(set(actual_relative) - set(expected))
    missing = sorted(set(expected) - set(actual_relative))
    if unexpected or missing:
        raise BuildError(f"unexpected or missing output files; extra={unexpected[:5]}, missing={missing[:5]}")
    for relative, path in actual_relative.items():
        data = path.read_bytes()
        validate_wav_bytes(data, relative)
        require(sha256_bytes(data) == expected[relative], f"processed SHA-256 mismatch: {relative}")


def reproduce_and_compare_outputs(source_map: dict, checkout: Path, output_root: Path) -> None:
    expected = expected_processed_hashes(source_map)
    with tempfile.TemporaryDirectory(prefix="day-objects-happening-verify-") as directory:
        fresh_root = Path(directory) / "Happenings"
        fresh_map = copy.deepcopy(source_map)
        fresh_records = render_bank(fresh_map, checkout, fresh_root)
        fresh_hashes = {path: record["output"]["sha256"] for path, record in fresh_records.items()}
        if fresh_hashes != expected:
            mismatches = sorted(path for path in set(fresh_hashes) | set(expected)
                                if fresh_hashes.get(path) != expected.get(path))
            raise BuildError(f"fresh reproduction rendered bytes differ from source map: {mismatches[:5]}")
        for relative in sorted(expected):
            suffix = relative.removeprefix("Happenings/")
            if (fresh_root / suffix).read_bytes() != (output_root / suffix).read_bytes():
                raise BuildError(f"fresh reproduction rendered bytes differ from checked output: {relative}")


def verify_checked_output(
    source_map: dict,
    checkout: Path,
    output_root: Path,
    *,
    reproduce: bool = True,
) -> None:
    for recipe in source_map["recipes"]:
        if recipe.get("input"):
            actual_input_hash = sha256_file(vcsl_input_path(checkout, recipe))
            require(actual_input_hash == recipe["input"]["sha256"],
                    f"stale or dirty original SHA-256 for recipe {recipe['id']:02d}")
        else:
            require(canonical_sha256(recipe["definition"]) == recipe.get("definitionSha256"),
                    f"stale generator definition SHA-256 for recipe {recipe['id']:02d}")
    expected = expected_processed_hashes(source_map)
    validate_output_inventory(output_root, expected)
    with MANIFEST_PATH.open("r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    with SOURCES_PATH.open("r", encoding="utf-8") as handle:
        sources = json.load(handle)
    validate_complete_metadata(source_map, manifest, sources)
    catalog_text = CATALOG_PATH.read_text(encoding="utf-8")
    catalog_hashes = dict(re.findall(r'        "(Happenings/[^"]+)": "([0-9a-f]{64})",', catalog_text))
    require(catalog_hashes == expected,
            "HappeningSoundCatalog does not match source map processed paths and hashes")
    if reproduce:
        reproduce_and_compare_outputs(source_map, checkout, output_root)


def compare_temporary_render(source_map: dict, records: dict[str, dict]) -> None:
    expected = expected_processed_hashes(source_map)
    actual = {path: record["output"]["sha256"] for path, record in records.items()}
    if actual != expected:
        mismatches = sorted(path for path in set(actual) | set(expected) if actual.get(path) != expected.get(path))
        raise BuildError(f"temporary render differs from checked output: {mismatches[:5]}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vcsl-checkout", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument(
        "--refresh-derived-metadata",
        action="store_true",
        help="explicitly refresh renderer identities and processed hashes; never changes original source hashes",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.verify_only and args.refresh_derived_metadata:
            raise BuildError("--verify-only and --refresh-derived-metadata are mutually exclusive")
        if args.refresh_derived_metadata:
            with SOURCE_MAP_PATH.open("r", encoding="utf-8") as handle:
                source_map = json.load(handle)
            validate_source_map(source_map, allow_stale_derived=True)
            source_map["rendererVersion"] = RENDERER_VERSION
            source_map["rendererImplementationSha256"] = renderer_implementation_sha256()
            source_map["renderFormat"] = expected_render_format()
            for recipe in source_map["recipes"]:
                if recipe.get("definition"):
                    recipe["definitionSha256"] = canonical_sha256(recipe["definition"])
                recipe["renderIdentitySha256"] = render_identity_for_recipe(recipe, source_map)
        else:
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
            update_sources(source_map)
            update_catalog(records)
            # The explicit --verify-only pass below performs the independent
            # reproduction. Avoid rendering all 102 assets twice in one
            # process so a bounded build remains inside the 60-second gate.
            verify_checked_output(source_map, checkout, output_root, reproduce=False)
        else:
            compare_temporary_render(load_source_map(), records)
        total_bytes = sum(record["bytes"] for record in records.values())
        print(f"rendered 102 deterministic WAVs ({total_bytes} bytes) at {output_root}")
        return 0
    except (BuildError, OSError, subprocess.CalledProcessError, json.JSONDecodeError,
            KeyError, TypeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
