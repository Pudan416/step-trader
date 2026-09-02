"""Deterministic measurements and bounded mastering for Happening events."""

from __future__ import annotations

from dataclasses import dataclass
import math


AUDIBLE_THRESHOLD = 10.0 ** (-60.0 / 20.0)
DBFS_FLOOR = -120.0
BOUNDARY_FADE_SECONDS = 0.005
ONSET_SECONDS = 0.050
SPECTRAL_BAND_COUNT = 24
ENVELOPE_WINDOW_COUNT = 12


class AudioMetricError(ValueError):
    """Raised when an event cannot be measured or mastered safely."""


@dataclass(frozen=True)
class MasteringTarget:
    rms_min_dbfs: float
    rms_max_dbfs: float
    peak_ceiling_dbfs: float = -6.0
    onset_ceiling_dbfs: float = -15.0
    maximum_gain_db: float = 12.0


@dataclass(frozen=True)
class EventMetrics:
    sample_peak_dbfs: float
    audible_rms_dbfs: float
    onset_rms_dbfs: float
    dc_dbfs: float
    duration_seconds: float
    spectral_bands: tuple[float, ...]
    envelope_windows: tuple[float, ...]


def amplitude_to_dbfs(value: float) -> float:
    return 20.0 * math.log10(max(abs(value), 1.0e-6))


def rms(values: list[float]) -> float:
    return math.sqrt(sum(value * value for value in values) / len(values)) if values else 0.0


def _validate_samples(samples: list[float], sample_rate: int) -> None:
    if sample_rate <= 0:
        raise AudioMetricError("sample rate must be positive")
    if not samples:
        raise AudioMetricError("event has no samples")
    if any(not math.isfinite(value) for value in samples):
        raise AudioMetricError("event contains non-finite samples")


def _audible_bounds(samples: list[float]) -> tuple[int, int] | None:
    first = next((index for index, value in enumerate(samples) if abs(value) >= AUDIBLE_THRESHOLD), None)
    if first is None:
        return None
    last = next(
        index
        for index in range(len(samples) - 1, -1, -1)
        if abs(samples[index]) >= AUDIBLE_THRESHOLD
    )
    return first, last


def _normalized_goertzel_bands(samples: list[float], sample_rate: int) -> tuple[float, ...]:
    if not any(samples):
        return (0.0,) * SPECTRAL_BAND_COUNT
    highest_frequency = min(12_000.0, sample_rate / 2.0)
    if highest_frequency <= 80.0:
        frequencies = [80.0] * SPECTRAL_BAND_COUNT
    else:
        frequency_ratio = (highest_frequency / 80.0) ** (1.0 / (SPECTRAL_BAND_COUNT - 1))
        frequencies = [80.0 * frequency_ratio ** band for band in range(SPECTRAL_BAND_COUNT)]
    magnitudes: list[float] = []
    for frequency in frequencies:
        omega = math.tau * frequency / sample_rate
        coefficient = 2.0 * math.cos(omega)
        previous = 0.0
        current = 0.0
        for sample in samples:
            next_value = sample + coefficient * current - previous
            previous, current = current, next_value
        power = max(current * current + previous * previous - coefficient * current * previous, 0.0)
        magnitudes.append(math.sqrt(power) / len(samples))
    total = sum(magnitudes)
    return tuple(value / total for value in magnitudes) if total else (0.0,) * SPECTRAL_BAND_COUNT


def _normalized_envelope_windows(samples: list[float]) -> tuple[float, ...]:
    if not any(samples):
        return (0.0,) * ENVELOPE_WINDOW_COUNT
    energies = []
    for window in range(ENVELOPE_WINDOW_COUNT):
        start = len(samples) * window // ENVELOPE_WINDOW_COUNT
        end = len(samples) * (window + 1) // ENVELOPE_WINDOW_COUNT
        energies.append(sum(value * value for value in samples[start:end]))
    total = sum(energies)
    return tuple(value / total for value in energies) if total else (0.0,) * ENVELOPE_WINDOW_COUNT


def measure_event(samples: list[float], sample_rate: int = 44_100) -> EventMetrics:
    _validate_samples(samples, sample_rate)
    audible_bounds = _audible_bounds(samples)
    audible_samples = (
        [value for value in samples if abs(value) >= AUDIBLE_THRESHOLD]
        if audible_bounds is not None
        else []
    )
    onset_samples = (
        samples[audible_bounds[0] : audible_bounds[0] + round(sample_rate * ONSET_SECONDS)]
        if audible_bounds is not None
        else []
    )
    return EventMetrics(
        sample_peak_dbfs=amplitude_to_dbfs(max(abs(value) for value in samples)),
        audible_rms_dbfs=amplitude_to_dbfs(rms(audible_samples)),
        onset_rms_dbfs=amplitude_to_dbfs(rms(onset_samples)),
        dc_dbfs=amplitude_to_dbfs(sum(samples) / len(samples)),
        duration_seconds=len(samples) / sample_rate,
        spectral_bands=_normalized_goertzel_bands(samples, sample_rate),
        envelope_windows=_normalized_envelope_windows(samples),
    )


def _apply_boundary_fades(samples: list[float], sample_rate: int) -> list[float]:
    faded = samples.copy()
    fade_frames = min(round(sample_rate * BOUNDARY_FADE_SECONDS), len(faded) // 2)
    if fade_frames:
        denominator = max(fade_frames - 1, 1)
        for index in range(fade_frames):
            gain = index / denominator
            faded[index] *= gain
            faded[-1 - index] *= gain
    if faded:
        faded[0] = 0.0
        faded[-1] = 0.0
    return faded


def _gain_limit_for_dbfs(current_dbfs: float, ceiling_dbfs: float) -> float:
    if current_dbfs <= DBFS_FLOOR:
        return math.inf
    return 10.0 ** ((ceiling_dbfs - current_dbfs) / 20.0)


def master_event(
    samples: list[float], target: MasteringTarget, sample_rate: int = 44_100
) -> list[float]:
    _validate_samples(samples, sample_rate)
    if target.rms_min_dbfs > target.rms_max_dbfs:
        raise AudioMetricError("RMS minimum exceeds RMS maximum")
    if target.maximum_gain_db < 0.0:
        raise AudioMetricError("maximum gain must not be negative")
    bounds = _audible_bounds(samples)
    if bounds is None:
        raise AudioMetricError("cannot master silent event")
    trimmed = _apply_boundary_fades(samples[bounds[0] : bounds[1] + 1], sample_rate)
    before = measure_event(trimmed, sample_rate)
    if before.audible_rms_dbfs <= DBFS_FLOOR:
        raise AudioMetricError("cannot master silent event after boundary fades")
    desired_rms_dbfs = (target.rms_min_dbfs + target.rms_max_dbfs) / 2.0
    desired_gain = 10.0 ** ((desired_rms_dbfs - before.audible_rms_dbfs) / 20.0)
    gain = min(
        desired_gain,
        _gain_limit_for_dbfs(before.sample_peak_dbfs, target.peak_ceiling_dbfs),
        _gain_limit_for_dbfs(before.onset_rms_dbfs, target.onset_ceiling_dbfs),
        10.0 ** (target.maximum_gain_db / 20.0),
    )
    mastered = [value * gain for value in trimmed]
    result = measure_event(mastered, sample_rate)
    if not target.rms_min_dbfs <= result.audible_rms_dbfs <= target.rms_max_dbfs:
        raise AudioMetricError("event cannot reach the requested RMS range within mastering limits")
    return mastered


def fingerprint_similarity(lhs: EventMetrics, rhs: EventMetrics) -> float:
    a = lhs.spectral_bands + lhs.envelope_windows
    b = rhs.spectral_bands + rhs.envelope_windows
    denominator = math.sqrt(sum(x * x for x in a) * sum(y * y for y in b))
    return 0.0 if denominator == 0 else sum(x * y for x, y in zip(a, b)) / denominator
