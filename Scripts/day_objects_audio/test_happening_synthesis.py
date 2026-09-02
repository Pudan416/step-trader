import math
import struct
import unittest

from Scripts.day_objects_audio import happening_synthesis as synthesis


SAMPLE_RATE = 44_100


def authored_definition_fixtures() -> list[dict]:
    """Hand-authored recipe-shaped inputs for every project-authored topology."""
    kinds = (
        "analog-ping",
        "fm-droplet",
        "pulse-pluck",
        "waveguide-string",
        "reed-blip",
        "reverse-pluck",
        "kalimba-modal",
        "ceramic-modal",
        "felt-key",
        "metal-bowl-modal",
        "glass-reverse",
        "chorus-kalimba",
        "nylon-waveguide",
        "sub-bloom",
        "filter-ping",
        "formant-droplet",
        "phase-distortion",
        "rubber-fm",
        "harmonic-stab",
        "breath-resonator",
        "modal-glass-cloud",
        "granular-shimmer",
        "reverse-glass-unpitched",
        "dust-impact",
        "breath-exhale",
    )
    tails = (
        "dry-damping",
        "short-room",
        "tape-echo",
        "dark-diffusion",
        "reverse-bloom",
        "chorus-decay",
        "modal-decay",
        "filtered-breath",
    )
    recipe_ids = (
        1, 2, 3, 4, 5, 6, 7, 8, 12, 13, 14, 15, 16,
        19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
    )
    return [
        {
            "id": recipe_id,
            "kind": kind,
            "tail": {"kind": tails[(index - 1) % len(tails)]},
        }
        for index, (recipe_id, kind) in enumerate(zip(recipe_ids, kinds), start=1)
    ]


def pcm16_bytes(samples: list[float]) -> bytes:
    return b"".join(
        struct.pack("<h", max(-32_768, min(32_767, round(sample * 32_767))))
        for sample in samples
    )


def oscillator_energy(samples: list[float], frequency_hz: float) -> float:
    start = round(SAMPLE_RATE * 0.10)
    stop = min(len(samples), start + round(SAMPLE_RATE * 0.30))
    cosine = sum(samples[index] * math.cos(math.tau * frequency_hz * index / SAMPLE_RATE)
                 for index in range(start, stop))
    sine = sum(samples[index] * math.sin(math.tau * frequency_hz * index / SAMPLE_RATE)
               for index in range(start, stop))
    return cosine * cosine + sine * sine


def rms(samples: list[float]) -> float:
    return math.sqrt(sum(sample * sample for sample in samples) / max(1, len(samples)))


def first_peak_frame(samples: list[float], fraction: float = 0.70) -> int:
    threshold = max(map(abs, samples)) * fraction
    return next(index for index, sample in enumerate(samples) if abs(sample) >= threshold)


def narrow_tone_concentration(samples: list[float]) -> float:
    """The strongest 10 Hz spectral line over an early 150 ms event window."""
    start = round(SAMPLE_RATE * 0.05)
    window = samples[start:start + round(SAMPLE_RATE * 0.15)]
    total_energy = sum(sample * sample for sample in window)
    strongest = 0.0
    for frequency_hz in range(60, 2_001, 10):
        cosine = sum(sample * math.cos(math.tau * frequency_hz * (start + index) / SAMPLE_RATE)
                     for index, sample in enumerate(window))
        sine = sum(sample * math.sin(math.tau * frequency_hz * (start + index) / SAMPLE_RATE)
                   for index, sample in enumerate(window))
        strongest = max(strongest, cosine * cosine + sine * sine)
    return strongest / max(total_energy * len(window) / 2.0, 1.0e-12)


class HappeningSynthesisTests(unittest.TestCase):
    def test_dispatch_membership_is_exact_and_rejects_extra_topologies(self):
        self.assertEqual(tuple(synthesis.AUTHORED_RENDERERS),
                         tuple(definition["kind"] for definition in authored_definition_fixtures()))
        self.assertEqual(tuple(synthesis.TAIL_RENDERERS), (
            "dry-damping", "short-room", "tape-echo", "dark-diffusion",
            "reverse-bloom", "chorus-decay", "modal-decay", "filtered-breath",
        ))

    def test_every_authored_topology_is_deterministic_and_declares_identity(self):
        for definition in authored_definition_fixtures():
            first = synthesis.render_authored(definition, root_midi=60, seed=37)
            second = synthesis.render_authored(definition, root_midi=60, seed=37)

            self.assertEqual(pcm16_bytes(first.samples), pcm16_bytes(second.samples))
            self.assertTrue(all(math.isfinite(sample) for sample in first.samples))
            self.assertGreater(max(map(abs, first.samples)), 1.0e-4)
            self.assertEqual(first.topology, definition["kind"])
            self.assertGreaterEqual(len(first.samples), round(SAMPLE_RATE * 0.8))
            self.assertLessEqual(len(first.samples), round(SAMPLE_RATE * 4.5))

    def test_every_authored_definition_reports_a_unique_attack_tail_pair(self):
        pairs = {
            (
                synthesis.render_authored(definition, root_midi=60, seed=37).attack_topology,
                synthesis.render_authored(definition, root_midi=60, seed=37).tail_topology,
            )
            for definition in authored_definition_fixtures()
        }

        self.assertEqual(len(pairs), len(authored_definition_fixtures()))

    def test_tonal_renderers_change_pitch_without_changing_duration(self):
        for definition in authored_definition_fixtures():
            if definition["id"] > 24:
                continue
            low = synthesis.render_authored(definition, root_midi=60, seed=37)
            high = synthesis.render_authored(definition, root_midi=72, seed=37)

            self.assertLessEqual(abs(len(low.samples) - len(high.samples)), 1)
            self.assertGreater(oscillator_energy(low.samples, synthesis.midi_to_hz(60)),
                               oscillator_energy(low.samples, synthesis.midi_to_hz(72)) * 1.2)
            self.assertGreater(oscillator_energy(high.samples, synthesis.midi_to_hz(72)),
                               oscillator_energy(high.samples, synthesis.midi_to_hz(60)) * 1.2)

    def test_tail_dispatches_are_bounded_deterministic_and_mono_safe(self):
        source = [
            math.sin(math.tau * 220 * frame / SAMPLE_RATE) * math.exp(-frame / 2_000)
            for frame in range(round(SAMPLE_RATE * 0.2))
        ]
        for tail_kind in synthesis.TAIL_RENDERERS:
            tail = {"kind": tail_kind}
            first = synthesis.apply_rendered_tail(source, root_midi=60, tail=tail, seed=37)
            second = synthesis.apply_rendered_tail(source, root_midi=60, tail=tail, seed=37)

            self.assertEqual(pcm16_bytes(first), pcm16_bytes(second))
            self.assertTrue(all(math.isfinite(sample) for sample in first))
            self.assertLess(max(map(abs, first)), 2.0)
            self.assertGreater(max(map(abs, first)), 1.0e-4)

    def test_frame_padding_api_keeps_reverse_bloom_count_bounded(self):
        self.assertTrue(
            hasattr(synthesis, "_pad_to_frames"),
            "frame counts need a dedicated padding API before tail rendering",
        )
        source = [0.25, -0.25]
        requested_frames = round(SAMPLE_RATE * 1.36)
        padded = synthesis._pad_to_frames(source, requested_frames)

        self.assertEqual(len(padded), requested_frames)
        self.assertEqual(padded[:2], source)

        rendered = synthesis.apply_rendered_tail(
            source,
            root_midi=60,
            tail={"kind": "reverse-bloom", "durationSeconds": 1.36},
            seed=37,
        )
        self.assertEqual(len(rendered), requested_frames)

    def test_frame_padding_api_keeps_modal_decay_count_bounded(self):
        source = [0.25, -0.25]
        requested_frames = round(SAMPLE_RATE * 1.36)
        rendered = synthesis.apply_rendered_tail(
            source,
            root_midi=60,
            tail={"kind": "modal-decay", "durationSeconds": 1.36},
            seed=37,
        )
        self.assertEqual(len(rendered), requested_frames)

    def test_reverse_bloom_duration_above_four_point_five_seconds_is_rejected_before_allocation(self):
        self.assertTrue(
            hasattr(synthesis, "MAX_RENDER_SECONDS"),
            "duration ceiling must exist before calling a tail renderer",
        )
        source = [0.25, -0.25]
        with self.assertRaisesRegex(ValueError, "4.5"):
            synthesis.apply_rendered_tail(
                source,
                root_midi=60,
                tail={"kind": "reverse-bloom", "durationSeconds": 4.5001},
                seed=37,
            )

    def test_modal_decay_duration_above_four_point_five_seconds_is_rejected_before_allocation(self):
        source = [0.25, -0.25]
        with self.assertRaisesRegex(ValueError, "4.5"):
            synthesis.apply_rendered_tail(
                source,
                root_midi=60,
                tail={"kind": "modal-decay", "durationSeconds": 4.5001},
                seed=37,
            )

    def test_dry_reverse_and_modal_tails_have_real_energy_after_the_body(self):
        source = [
            math.sin(math.tau * 220 * frame / SAMPLE_RATE) * math.exp(-frame / 2_000)
            for frame in range(round(SAMPLE_RATE * 0.2))
        ]
        for tail_kind in ("dry-damping", "reverse-bloom", "modal-decay"):
            rendered = synthesis.apply_rendered_tail(source, root_midi=60,
                                                     tail={"kind": tail_kind}, seed=37)
            post_body = rendered[len(source):len(source) + round(SAMPLE_RATE * 0.12)]
            self.assertGreater(rms(post_body), 1.0e-4, tail_kind)

    def test_authored_events_have_measurable_attack_body_and_post_body_tail_stages(self):
        attack_stop = round(SAMPLE_RATE * 0.08)
        body_stop = round(SAMPLE_RATE * 0.70)
        tail_stop = round(SAMPLE_RATE * 0.80)
        for definition in authored_definition_fixtures():
            samples = synthesis.render_authored(definition, root_midi=60, seed=37).samples
            self.assertGreater(rms(samples[:attack_stop]), 1.0e-4, definition["kind"])
            self.assertGreater(rms(samples[attack_stop:body_stop]), 1.0e-4, definition["kind"])
            self.assertGreater(rms(samples[body_stop:tail_stop]), 1.0e-5, definition["kind"])

    def test_sub_bloom_and_reverse_glass_reach_an_identifiable_attack_within_80ms(self):
        for kind in ("sub-bloom", "reverse-glass-unpitched"):
            definition = next(item for item in authored_definition_fixtures() if item["kind"] == kind)
            attack_frame = first_peak_frame(
                synthesis.render_authored(definition, root_midi=60, seed=37).samples
            )
            self.assertGreaterEqual(attack_frame, round(SAMPLE_RATE * 0.003), kind)
            self.assertLessEqual(attack_frame, round(SAMPLE_RATE * 0.08), kind)

    def test_reference_textures_and_unpitched_events_are_root_independent(self):
        for definition in authored_definition_fixtures():
            if definition["id"] < 25:
                continue
            low = synthesis.render_authored(definition, root_midi=48, seed=37)
            high = synthesis.render_authored(definition, root_midi=72, seed=37)
            self.assertEqual(pcm16_bytes(low.samples), pcm16_bytes(high.samples), definition["kind"])

    def test_unpitched_events_do_not_contain_a_stable_narrow_tonal_peak(self):
        for definition in authored_definition_fixtures():
            if definition["id"] < 28:
                continue
            samples = synthesis.render_authored(definition, root_midi=60, seed=37).samples
            self.assertLess(narrow_tone_concentration(samples), 0.25, definition["kind"])


if __name__ == "__main__":
    unittest.main()
