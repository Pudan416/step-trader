import copy
import hashlib
import importlib.util
import json
import math
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).with_name("build_happening_bank.py")
MODULE_SPEC = importlib.util.spec_from_file_location("build_happening_bank", MODULE_PATH)
if MODULE_SPEC is None or MODULE_SPEC.loader is None:
    raise RuntimeError(f"cannot load {MODULE_PATH}")
bank = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(bank)


class HappeningBankGeneratorTests(unittest.TestCase):
    def test_dirty_pinned_input_is_rejected_even_when_head_is_pinned(self):
        with tempfile.TemporaryDirectory() as directory:
            checkout = Path(directory)
            subprocess.run(["git", "init", "-q", str(checkout)], check=True)
            subprocess.run(["git", "-C", str(checkout), "config", "user.name", "Test"], check=True)
            subprocess.run(["git", "-C", str(checkout), "config", "user.email", "test@example.com"], check=True)
            source = checkout / "sample.wav"
            source.write_bytes(b"committed source")
            subprocess.run(["git", "-C", str(checkout), "add", "sample.wav"], check=True)
            subprocess.run(["git", "-C", str(checkout), "commit", "-qm", "fixture"], check=True)
            revision = subprocess.check_output(
                ["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True
            ).strip()
            source_map = {
                "recipes": [{
                    "id": 7,
                    "input": {
                        "path": "07 sample.wav",
                        "rootMIDI": 60,
                        "sha256": hashlib.sha256(b"committed source").hexdigest(),
                    },
                }]
            }
            source.write_bytes(b"dirty replacement")

            with mock.patch.object(bank, "PINNED_VCSL_REVISION", revision):
                with self.assertRaisesRegex(bank.BuildError, "dirty|committed|SHA-256"):
                    bank.validate_vcsl_checkout(checkout, source_map)

    def test_render_identity_covers_complete_recipe_and_renderer_inputs(self):
        source_map = bank.load_source_map()
        recipe = source_map["recipes"][0]
        baseline = bank.render_identity_for_recipe(recipe, source_map)
        mutations = [
            ("seed", lambda value: value + 1),
            ("rootMIDIs", lambda value: value[:-1]),
            ("sourceKey", lambda _: "vcsl"),
            ("definition", lambda value: {**value, "decay": value["decay"] + 0.1}),
        ]
        for field, mutation in mutations:
            changed = copy.deepcopy(recipe)
            changed[field] = mutation(changed[field])
            self.assertNotEqual(
                bank.render_identity_for_recipe(changed, source_map), baseline, field
            )
        changed_map = copy.deepcopy(source_map)
        changed_map["rendererVersion"] += "-changed"
        self.assertNotEqual(bank.render_identity_for_recipe(recipe, changed_map), baseline)
        changed_map = copy.deepcopy(source_map)
        changed_map["rendererImplementationSha256"] = "0" * 64
        self.assertNotEqual(bank.render_identity_for_recipe(recipe, changed_map), baseline)

    def test_stale_seed_root_and_renderer_identity_are_rejected(self):
        source_map = bank.load_source_map()
        for mutate in (
            lambda value: value["recipes"][0]["definition"].__setitem__("decay", 99.0),
            lambda value: value["recipes"][0].__setitem__("seed", 999),
            lambda value: value["recipes"][0].__setitem__("rootMIDIs", [72]),
            lambda value: value.__setitem__("rendererVersion", "stale-renderer"),
            lambda value: value.__setitem__("rendererImplementationSha256", "0" * 64),
        ):
            changed = copy.deepcopy(source_map)
            mutate(changed)
            with self.assertRaisesRegex(bank.BuildError, "render identity|renderer"):
                bank.validate_render_identities(changed)

    def test_complete_metadata_divergence_is_rejected(self):
        source_map = bank.load_source_map()
        manifest = json.loads(bank.MANIFEST_PATH.read_text())
        sources = json.loads(bank.SOURCES_PATH.read_text())
        happening_index = next(
            index for index, asset in enumerate(manifest["assets"])
            if asset["path"].startswith("Happenings/07/")
        )
        mutations = [
            lambda value: value["assets"][happening_index].__setitem__("rootMIDINote", 1),
            lambda value: value["assets"][happening_index].__setitem__("sourceKey", "project-authored"),
            lambda value: value["assets"][happening_index]["sourceFiles"][0].__setitem__("sha256", "0" * 64),
            lambda value: value["assets"][happening_index].__setitem__("licenseFilename", "wrong.txt"),
            lambda value: value["assets"][happening_index]["conversion"].__setitem__("sampleRateHz", 48_000),
            lambda value: value["assets"][happening_index].__setitem__("offlinePitchTransformSemitones", 99),
        ]
        for mutate in mutations:
            changed = copy.deepcopy(manifest)
            mutate(changed)
            with self.assertRaises(bank.BuildError):
                bank.validate_complete_metadata(source_map, changed, sources)
        changed_sources = copy.deepcopy(sources)
        vcsl = next(source for source in changed_sources if source["project"] == "VCSL")
        vcsl["selectedPaths"] = vcsl["selectedPaths"][:-1]
        with self.assertRaises(bank.BuildError):
            bank.validate_complete_metadata(source_map, manifest, changed_sources)

    def test_output_inventory_rejects_extra_non_wav_regular_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            wav = root / "01/C5.wav"
            wav.parent.mkdir(parents=True)
            wav_data = bank.wav_bytes([0] * bank.MIN_DURATION_FRAMES)
            wav.write_bytes(wav_data)
            expected = {"Happenings/01/C5.wav": hashlib.sha256(wav_data).hexdigest()}
            bank.validate_output_inventory(root, expected)
            (root / "source-master.flac").write_bytes(b"must not ship")
            with self.assertRaisesRegex(bank.BuildError, "extra|unexpected"):
                bank.validate_output_inventory(root, expected)

    def test_band_limited_pitch_shift_suppresses_old_linear_alias(self):
        sample_rate = bank.SAMPLE_RATE
        source = [0.8 * math.sin(math.tau * 18_000 * index / sample_rate) for index in range(sample_rate)]
        shifted = bank.resample_and_pitch(source, sample_rate, 12)
        interior = shifted[bank.RESAMPLER_TAPS : -bank.RESAMPLER_TAPS]
        rms = math.sqrt(sum(value * value for value in interior) / len(interior))
        self.assertLess(rms, 0.03)

    def test_six_second_bound_uses_long_taper_and_low_tail_energy(self):
        source = [0.5] * (bank.SAMPLE_RATE * 7)
        pcm = bank.trim_fade_normalize(source)
        self.assertEqual(len(pcm), bank.MAX_DURATION_FRAMES)
        tail = pcm[-round(bank.SAMPLE_RATE * 0.05) :]
        tail_rms = math.sqrt(sum(value * value for value in tail) / len(tail)) / 32767.0
        tail_dbfs = 20 * math.log10(max(tail_rms, 1e-12))
        self.assertLessEqual(tail_dbfs, bank.TAIL_BOUNDARY_RMS_DBFS)
        self.assertEqual(pcm[0], 0)
        self.assertEqual(pcm[-1], 0)

    def test_malformed_source_map_fails_with_actionable_build_error(self):
        source_map = bank.load_source_map()
        malformed_values = [
            {**source_map, "recipes": "not-an-array"},
            {**source_map, "renderFormat": {"sampleRateHz": "fast"}},
            {**source_map, "recipes": [{"id": 1}]},
        ]
        for malformed in malformed_values:
            with self.assertRaises(bank.BuildError):
                bank.validate_source_map(malformed)

    @unittest.skipUnless(
        Path(os.environ.get("DAY_OBJECTS_VCSL_CHECKOUT", "/tmp/day-objects-vcsl")).is_dir(),
        "set DAY_OBJECTS_VCSL_CHECKOUT to run immutable full rerender regression",
    )
    def test_reproduction_rejects_consistently_rehashed_tampered_wav(self):
        checkout = Path(os.environ.get("DAY_OBJECTS_VCSL_CHECKOUT", "/tmp/day-objects-vcsl"))
        source_map = bank.load_source_map()
        with tempfile.TemporaryDirectory() as directory:
            output_root = Path(directory) / "Happenings"
            shutil.copytree(bank.DEFAULT_OUTPUT_ROOT, output_root)
            target = output_root / "01/C5.wav"
            data = bytearray(target.read_bytes())
            data[-100] ^= 1
            target.write_bytes(data)
            changed = copy.deepcopy(source_map)
            output = next(
                output for recipe in changed["recipes"] for output in recipe["outputs"]
                if output["path"] == "Happenings/01/C5.wav"
            )
            output["sha256"] = hashlib.sha256(data).hexdigest()

            with self.assertRaisesRegex(bank.BuildError, "reproduce|rendered bytes"):
                bank.reproduce_and_compare_outputs(changed, checkout, output_root)


if __name__ == "__main__":
    unittest.main()
