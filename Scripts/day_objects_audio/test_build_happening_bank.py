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
import wave
from itertools import combinations
from pathlib import Path
from unittest import mock

from Scripts.day_objects_audio import happening_audio_metrics as audio_metrics

MODULE_PATH = Path(__file__).with_name("build_happening_bank.py")
MODULE_SPEC = importlib.util.spec_from_file_location("build_happening_bank", MODULE_PATH)
if MODULE_SPEC is None or MODULE_SPEC.loader is None:
    raise RuntimeError(f"cannot load {MODULE_PATH}")
bank = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(bank)


class HappeningBankGeneratorTests(unittest.TestCase):
    @unittest.skipUnless(
        os.environ.get("DAY_OBJECTS_RECIPE_ID"),
        "set DAY_OBJECTS_RECIPE_ID to run the bounded one-recipe render gate",
    )
    def test_single_recipe_render_meets_identity_duration_and_mastering_gates(self):
        recipe_id = int(os.environ["DAY_OBJECTS_RECIPE_ID"])
        checkout = Path(os.environ.get("DAY_OBJECTS_VCSL_CHECKOUT", "/tmp/day-objects-vcsl"))
        source_map = json.loads(bank.SOURCE_MAP_PATH.read_text())
        bank.validate_source_map(source_map, allow_stale_derived=True)
        recipe = source_map["recipes"][recipe_id - 1]
        self.assertEqual(recipe["id"], recipe_id)
        source_samples = None
        source_rate = bank.SAMPLE_RATE
        if recipe.get("input"):
            input_path = bank.vcsl_input_path(checkout, recipe)
            self.assertEqual(bank.sha256_file(input_path), recipe["input"]["sha256"])
            source_samples, source_rate = bank.read_pcm_wav(input_path)

        rendered_metrics = []
        for root_midi in recipe["rootMIDIs"]:
            if source_samples is None:
                rendered = bank.render_generated(recipe, root_midi)
            else:
                pitched = bank.resample_and_pitch(
                    source_samples, source_rate, root_midi - recipe["input"]["rootMIDI"]
                )
                rendered = bank.render_recorded(recipe, pitched, root_midi)
            self.assertEqual(rendered.topology, recipe["topology"])
            self.assertEqual(rendered.attack_topology, recipe["attackTopology"])
            self.assertEqual(rendered.tail_topology, recipe["tailTopology"])
            self.assertLessEqual(len(rendered.samples), bank.MAX_DURATION_FRAMES)
            prepared = bank.prepare_for_mastering(rendered.samples, bank.mastering_target(recipe))
            pcm = bank.trim_fade_master(prepared, bank.mastering_target(recipe))
            measured = audio_metrics.measure_event(
                [sample / 32767.0 for sample in pcm], bank.SAMPLE_RATE
            )
            rms_range = (-22.0, -18.0) if recipe_id <= 24 else (-26.0, -21.0)
            self.assertLessEqual(measured.sample_peak_dbfs, -6.0 + 0.01)
            self.assertGreaterEqual(measured.audible_rms_dbfs, rms_range[0] - 0.05)
            self.assertLessEqual(measured.audible_rms_dbfs, rms_range[1] + 0.05)
            self.assertLessEqual(measured.onset_rms_dbfs, -15.0 + 0.05)
            self.assertLessEqual(measured.dc_dbfs, -50.0 + 0.05)
            rendered_metrics.append(measured)
        print(
            f"recipe={recipe_id:02d} roots={len(rendered_metrics)} "
            f"peak={max(value.sample_peak_dbfs for value in rendered_metrics):.2f}dBFS "
            f"rms={min(value.audible_rms_dbfs for value in rendered_metrics):.2f}.."
            f"{max(value.audible_rms_dbfs for value in rendered_metrics):.2f}dBFS"
        )

    def test_retimbre_source_map_has_exact_identity_palette_topology_and_roots(self):
        source_map = json.loads(bank.SOURCE_MAP_PATH.read_text())
        recipes = source_map["recipes"]
        expected_names = [
            "Warm analog ping", "Glass FM droplet", "Muted pulse pluck",
            "Hollow string", "Air reed blip", "Reverse pluck bloom",
            "Wooden kalimba", "Ceramic knock", "Soft marimba", "Balafon brush",
            "Muted vibraphone", "Felt key", "Soft metal bowl", "Glass tap bloom",
            "Chorus kalimba", "Nylon pizzicato", "Dark tubular bell", "Distant chime",
            "Sub bloom", "Analog filter ping", "Vocal droplet", "Phase-distortion bead",
            "Rubber FM bubble", "Bowed harmonic stab", "Breath resonator",
            "Bowed glass cloud", "Granular shimmer", "Reverse glass gesture",
            "Soft dust impact", "Airy exhale",
        ]
        expected_topologies = [
            "analog-ping", "fm-droplet", "pulse-pluck", "waveguide-string", "reed-blip",
            "reverse-pluck", "kalimba-modal", "ceramic-modal", "vcsl-marimba-dark",
            "vcsl-balafon-dry", "vcsl-vibe-chorus", "felt-key", "metal-bowl-modal",
            "glass-reverse", "chorus-kalimba", "nylon-waveguide", "vcsl-tubular-dark",
            "vcsl-chime-dark", "sub-bloom", "filter-ping", "formant-droplet",
            "phase-distortion", "rubber-fm", "harmonic-stab", "breath-resonator",
            "modal-glass-cloud", "granular-shimmer", "reverse-glass-unpitched",
            "dust-impact", "breath-exhale",
        ]
        synth_ids = {1, 2, 3, 4, 5, 8, 19, 20, 21, 22}
        organic_ids = {7, 9, 10, 12, 16, 17, 18, 28, 29, 30}
        expected_palettes = [
            "synth" if recipe_id in synth_ids else "organic" if recipe_id in organic_ids else "hybrid"
            for recipe_id in range(1, 31)
        ]
        expected_vcsl_paths = [
            "09 Idiophones/Struck Idiophones/Marimba/Marimba_hit_Outrigger_C4_soft_01.wav",
            "10 Idiophones/Struck Idiophones/Balafon/Soft Mallet/EthnicXylo_softM_C4_vl2_rr1_Mid.wav",
            "11 Idiophones/Struck Idiophones/Vibraphone/Soft Mallets/Vibes_soft_C5_v1_rr1_Main.wav",
            "17 Idiophones/Struck Idiophones/Tubular Bells 1/chimes_C4_p_rr1.wav",
            "18 Idiophones/Struck Idiophones/Tubular Bells 1/chimes_D4_p_rr1.wav",
        ]

        self.assertEqual(source_map["rendererVersion"], "happening-bank-v3")
        self.assertEqual(source_map["renderFormat"]["peakDBFS"], -6.0)
        self.assertEqual(source_map["renderFormat"]["onsetRMSDBFS"], -15.0)
        self.assertEqual(source_map["renderFormat"]["dcCeilingDBFS"], -50.0)
        self.assertEqual(source_map["renderFormat"]["maximumGainDB"], 12.0)
        self.assertEqual([recipe["workingName"] for recipe in recipes], expected_names)
        self.assertEqual([recipe["topology"] for recipe in recipes], expected_topologies)
        self.assertEqual([recipe["paletteKind"] for recipe in recipes], expected_palettes)
        self.assertEqual([recipe["masteringFamily"] for recipe in recipes],
                         ["tonal-organic"] * 24 + ["texture"] * 6)
        self.assertEqual([recipe["input"]["path"] for recipe in recipes if recipe.get("input")],
                         expected_vcsl_paths)
        self.assertEqual({palette: expected_palettes.count(palette) for palette in set(expected_palettes)},
                         {"synth": 10, "organic": 10, "hybrid": 10})
        self.assertGreaterEqual(len(set(expected_topologies)), 12)
        self.assertEqual(len({(recipe["attackTopology"], recipe["tailTopology"])
                              for recipe in recipes}), 30)
        self.assertTrue(all(len(recipe["rootMIDIs"]) == (4 if recipe["id"] <= 24 else 1)
                            for recipe in recipes))
        self.assertTrue(all({root % 12 for root in recipe["rootMIDIs"]} == {0, 3, 6, 9}
                            for recipe in recipes[:24]))
        self.assertEqual(sum(len(recipe["outputs"]) for recipe in recipes), 102)

    def test_retimbre_source_map_validation_rejects_identity_and_shape_mutations(self):
        source_map = json.loads(bank.SOURCE_MAP_PATH.read_text())
        mutations = [
            lambda value: value["recipes"][0].__setitem__("workingName", ""),
            lambda value: value["recipes"][0].__setitem__("paletteKind", "wrong"),
            lambda value: value["recipes"][0].__setitem__("topology", ""),
            lambda value: value["recipes"][0].__setitem__("attackTopology", ""),
            lambda value: value["recipes"][0].__setitem__("tailTopology", ""),
            lambda value: (
                value["recipes"][0].update({"attackTopology": "duplicate", "tailTopology": "duplicate"}),
                value["recipes"][1].update({"attackTopology": "duplicate", "tailTopology": "duplicate"}),
            ),
            lambda value: value["recipes"][0].__setitem__("rootMIDIs", [72]),
        ]
        for mutate in mutations:
            changed = copy.deepcopy(source_map)
            mutate(changed)
            with self.assertRaises(bank.BuildError):
                bank.validate_source_map(changed, allow_stale_derived=True)

    def test_checked_bank_meets_mastering_and_nonstationary_texture_gates(self):
        source_map = json.loads(bank.SOURCE_MAP_PATH.read_text())
        for recipe in source_map["recipes"]:
            representative = recipe["outputs"][0]["path"].removeprefix("Happenings/")
            samples, sample_rate = bank.read_pcm_wav(bank.DEFAULT_OUTPUT_ROOT / representative)
            measured = audio_metrics.measure_event(samples, sample_rate)
            rms_range = (-22.0, -18.0) if recipe["id"] <= 24 else (-26.0, -21.0)
            self.assertLessEqual(measured.sample_peak_dbfs, -6.0 + 0.01, recipe["workingName"])
            self.assertGreaterEqual(measured.audible_rms_dbfs, rms_range[0] - 0.05,
                                    recipe["workingName"])
            self.assertLessEqual(measured.audible_rms_dbfs, rms_range[1] + 0.05,
                                 recipe["workingName"])
            self.assertLessEqual(measured.onset_rms_dbfs, -15.0 + 0.05, recipe["workingName"])
            self.assertLessEqual(measured.dc_dbfs, -50.0 + 0.05, recipe["workingName"])
            self.assertEqual(samples[0], 0.0, recipe["workingName"])
            self.assertEqual(samples[-1], 0.0, recipe["workingName"])
            if recipe["id"] >= 28:
                windows = measured.envelope_windows
                audible_rms = 10.0 ** (measured.audible_rms_dbfs / 20.0)
                self.assertGreater(max(windows), audible_rms * 1.5,
                                   recipe["workingName"])
                self.assertGreater(max(windows) - min(windows), 0.14, recipe["workingName"])
                self.assertLess(windows[-1], max(windows) * 0.45, recipe["workingName"])

    def test_historical_groups_have_distinct_fingerprints_and_no_duplicate_bytes(self):
        source_map = json.loads(bank.SOURCE_MAP_PATH.read_text())
        checked_bytes = [path.read_bytes() for path in sorted(bank.DEFAULT_OUTPUT_ROOT.rglob("*.wav"))]
        self.assertEqual(len(checked_bytes), 102)
        self.assertEqual(len({hashlib.sha256(data).digest() for data in checked_bytes}), 102)

        measured = {}
        for recipe in source_map["recipes"]:
            representative = recipe["outputs"][0]["path"].removeprefix("Happenings/")
            samples, sample_rate = bank.read_pcm_wav(bank.DEFAULT_OUTPUT_ROOT / representative)
            measured[recipe["id"]] = audio_metrics.measure_event(samples, sample_rate)
        for recipe_ids in (
            range(1, 7), range(7, 9), range(9, 13), range(13, 17),
            range(19, 25), range(25, 28), range(28, 31),
        ):
            for lhs_id, rhs_id in combinations(recipe_ids, 2):
                similarity = audio_metrics.fingerprint_similarity(measured[lhs_id], measured[rhs_id])
                self.assertLess(similarity, 0.97, f"{lhs_id:02d}/{rhs_id:02d}: {similarity}")

    @unittest.skipUnless(
        Path(os.environ.get("DAY_OBJECTS_VCSL_CHECKOUT", "/tmp/day-objects-vcsl")).is_dir(),
        "set DAY_OBJECTS_VCSL_CHECKOUT to check retained chime high-frequency attenuation",
    )
    def test_retained_chimes_reduce_energy_above_5500_hz_by_four_db(self):
        checkout = Path(os.environ.get("DAY_OBJECTS_VCSL_CHECKOUT", "/tmp/day-objects-vcsl"))
        source_map = json.loads(bank.SOURCE_MAP_PATH.read_text())

        def high_frequency_balance_db(samples: list[float], sample_rate: int) -> float:
            filtered = samples
            for _ in range(4):
                filtered = bank.synthesis.one_pole_highpass(filtered, 5_500.0)
            high_rms = math.sqrt(sum(sample * sample for sample in filtered) / len(filtered))
            full_rms = math.sqrt(sum(sample * sample for sample in samples) / len(samples))
            return 20.0 * math.log10(max(high_rms, 1.0e-12) / max(full_rms, 1.0e-12))

        for recipe_id in (17, 18):
            recipe = source_map["recipes"][recipe_id - 1]
            source_samples, source_rate = bank.read_pcm_wav(bank.vcsl_input_path(checkout, recipe))
            output_path = recipe["outputs"][0]["path"].removeprefix("Happenings/")
            processed_samples, processed_rate = bank.read_pcm_wav(bank.DEFAULT_OUTPUT_ROOT / output_path)
            reduction = high_frequency_balance_db(source_samples, source_rate) - high_frequency_balance_db(
                processed_samples, processed_rate)
            self.assertGreaterEqual(reduction, 4.0, f"recipe {recipe_id:02d}: {reduction:.2f} dB")

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
            ("definition", lambda value: {**value, "kind": "changed-topology"}),
            ("workingName", lambda _: "Changed identity"),
            ("paletteKind", lambda _: "organic"),
            ("topology", lambda _: "changed-topology"),
            ("attackTopology", lambda _: "changed-attack"),
            ("tailTopology", lambda _: "changed-tail"),
            ("masteringFamily", lambda _: "texture"),
            ("tail", lambda _: {"kind": "short-room", "durationSeconds": 3.25}),
        ]
        for field, mutation in mutations:
            changed = copy.deepcopy(recipe)
            changed[field] = mutation(changed.get(field))
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
            lambda value: value["assets"][happening_index].__setitem__("sourceKey", "vcsl"),
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

    def test_mastered_pcm_obeys_v3_peak_rms_and_boundary_contract(self):
        source = [
            0.2 * math.sin(math.tau * 220 * frame / bank.SAMPLE_RATE)
            for frame in range(bank.SAMPLE_RATE)
        ]
        target = bank.MASTERING_TARGETS["tonal-organic"]
        pcm = bank.trim_fade_master(source, target)
        measured = audio_metrics.measure_event([sample / 32767.0 for sample in pcm], bank.SAMPLE_RATE)
        self.assertLessEqual(measured.sample_peak_dbfs, -6.0 + 0.01)
        self.assertGreaterEqual(measured.audible_rms_dbfs, -22.0 - 0.05)
        self.assertLessEqual(measured.audible_rms_dbfs, -18.0 + 0.05)
        self.assertLessEqual(measured.onset_rms_dbfs, -15.0 + 0.05)
        self.assertLessEqual(measured.dc_dbfs, -50.0 + 0.05)
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
