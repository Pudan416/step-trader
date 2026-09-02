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


class HappeningSynthesisTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
