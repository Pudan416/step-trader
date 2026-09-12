import math
import unittest

from Scripts.day_objects_audio import happening_audio_metrics as metrics


SAMPLE_RATE = 44_100


def full_scale_sine_fixture() -> list[float]:
    return [
        math.sin(math.tau * 441 * index / SAMPLE_RATE)
        for index in range(SAMPLE_RATE)
    ]


def dc_biased_sine_fixture() -> list[float]:
    return [
        0.05 + 0.02 * math.sin(math.tau * 441 * index / SAMPLE_RATE)
        for index in range(SAMPLE_RATE)
    ]


def rendered_transient_fixture() -> list[float]:
    transient_frames = round(SAMPLE_RATE * 0.020)
    tail_frames = round(SAMPLE_RATE * 0.480)
    return (
        [0.0]
        + [0.05 * math.sin(math.tau * 800 * index / SAMPLE_RATE)
           for index in range(transient_frames)]
        + [0.04 * math.sin(math.tau * 230 * index / SAMPLE_RATE)
           for index in range(tail_frames)]
        + [0.0]
    )


class HappeningAudioMetricsTests(unittest.TestCase):
    def test_measure_event_reports_full_scale_sine_metrics_and_fingerprint_shape(self):
        result = metrics.measure_event(full_scale_sine_fixture())

        self.assertAlmostEqual(result.sample_peak_dbfs, 0.0, places=2)
        self.assertAlmostEqual(result.audible_rms_dbfs, -2.9226, places=2)
        self.assertAlmostEqual(result.duration_seconds, 1.0, places=6)
        self.assertEqual(len(result.spectral_bands), 24)
        self.assertEqual(len(result.envelope_windows), 12)

    def test_measure_event_reports_dc_bias(self):
        samples = [0.25 + 0.1 * math.sin(math.tau * 441 * index / SAMPLE_RATE)
                   for index in range(SAMPLE_RATE)]

        result = metrics.measure_event(samples)

        self.assertAlmostEqual(result.dc_dbfs, -12.0412, places=2)

    def test_measure_event_converts_silent_energy_to_negative_120_dbfs(self):
        result = metrics.measure_event([0.0] * round(SAMPLE_RATE * 0.1))

        self.assertEqual(result.sample_peak_dbfs, -120.0)
        self.assertEqual(result.audible_rms_dbfs, -120.0)
        self.assertEqual(result.onset_rms_dbfs, -120.0)
        self.assertEqual(result.dc_dbfs, -120.0)

    def test_measure_event_rejects_non_finite_input(self):
        with self.assertRaises(metrics.AudioMetricError):
            metrics.measure_event([0.0, math.nan])
        with self.assertRaises(metrics.AudioMetricError):
            metrics.measure_event([0.0, math.inf])

    def test_mastering_honors_rms_peak_onset_and_gain_limits(self):
        samples = rendered_transient_fixture()
        mastered = metrics.master_event(samples, metrics.MasteringTarget(-22, -18))
        result = metrics.measure_event(mastered)

        self.assertLessEqual(result.sample_peak_dbfs, -6.0 + 0.05)
        self.assertLessEqual(result.onset_rms_dbfs, -15.0 + 0.05)
        self.assertGreaterEqual(result.audible_rms_dbfs, -22.0 - 0.05)
        self.assertLessEqual(result.audible_rms_dbfs, -18.0 + 0.05)
        self.assertLessEqual(max(abs(value) for value in mastered), 0.05 * 10.0 ** (12.0 / 20.0) + 1e-9)
        self.assertEqual(mastered[0], 0.0)
        self.assertEqual(mastered[-1], 0.0)

    def test_mastering_full_scale_sine_obeys_bounded_family_gates(self):
        mastered = metrics.master_event(full_scale_sine_fixture(), metrics.MasteringTarget(-22, -18))
        result = metrics.measure_event(mastered)

        self.assertLessEqual(result.sample_peak_dbfs, -6.0 + 0.05)
        self.assertLessEqual(result.onset_rms_dbfs, -15.0 + 0.05)
        self.assertGreaterEqual(result.audible_rms_dbfs, -22.0 - 0.05)
        self.assertLessEqual(result.audible_rms_dbfs, -18.0 + 0.05)
        self.assertEqual(mastered[0], 0.0)
        self.assertEqual(mastered[-1], 0.0)

    def test_mastering_removes_dc_bias_while_preserving_all_mastering_gates(self):
        mastered = metrics.master_event(dc_biased_sine_fixture(), metrics.MasteringTarget(-30, -28))
        result = metrics.measure_event(mastered)

        self.assertLessEqual(result.dc_dbfs, -50.0)
        self.assertLessEqual(result.sample_peak_dbfs, -6.0 + 0.05)
        self.assertLessEqual(result.onset_rms_dbfs, -15.0 + 0.05)
        self.assertGreaterEqual(result.audible_rms_dbfs, -30.0 - 0.05)
        self.assertLessEqual(result.audible_rms_dbfs, -28.0 + 0.05)
        self.assertEqual(mastered[0], 0.0)
        self.assertEqual(mastered[-1], 0.0)

    def test_mastering_rejects_silence_or_an_event_needing_more_than_12_db_gain(self):
        target = metrics.MasteringTarget(-22, -18)

        with self.assertRaises(metrics.AudioMetricError):
            metrics.master_event([0.0] * SAMPLE_RATE, target)
        with self.assertRaises(metrics.AudioMetricError):
            metrics.master_event([0.01] * SAMPLE_RATE, target)

    def test_mastering_rejects_non_finite_input(self):
        with self.assertRaises(metrics.AudioMetricError):
            metrics.master_event([0.0, -math.inf], metrics.MasteringTarget(-22, -18))

    def test_identical_fingerprints_have_similarity_one(self):
        event = metrics.measure_event(full_scale_sine_fixture())

        self.assertAlmostEqual(metrics.fingerprint_similarity(event, event), 1.0, places=12)


if __name__ == "__main__":
    unittest.main()
