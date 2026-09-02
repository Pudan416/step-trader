"""Deterministic, mono attack/body/tail renders for authored Happening events.

This module intentionally depends only on Python's standard library.  It does
not master, write WAV files, or know about the production source map; those are
the builder's responsibilities.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
import random


SAMPLE_RATE = 44_100
_BOUND = 1.999


@dataclass(frozen=True)
class RenderedEvent:
    samples: list[float]
    topology: str
    attack_topology: str
    tail_topology: str


def midi_to_hz(midi: int) -> float:
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def clamp_samples(samples: list[float], limit: float = _BOUND) -> list[float]:
    return [max(-limit, min(limit, value)) for value in samples]


def seeded_white_noise(frames: int, seed: int) -> list[float]:
    generator = random.Random(seed)
    return [generator.uniform(-1.0, 1.0) for _ in range(frames)]


def seeded_brown_noise(frames: int, seed: int) -> list[float]:
    value = 0.0
    result: list[float] = []
    for noise in seeded_white_noise(frames, seed):
        value = max(-1.0, min(1.0, value * 0.985 + noise * 0.055))
        result.append(value)
    return result


def sine_oscillator(frequency_hz: float, frames: int, phase: float = 0.0) -> list[float]:
    return [math.sin(math.tau * (phase + frequency_hz * frame / SAMPLE_RATE)) for frame in range(frames)]


def triangle_oscillator(frequency_hz: float, frames: int) -> list[float]:
    return [2.0 * abs(2.0 * ((frequency_hz * frame / SAMPLE_RATE) % 1.0) - 1.0) - 1.0
            for frame in range(frames)]


def pulse_oscillator(frequency_hz: float, frames: int, width: float = 0.18) -> list[float]:
    return [1.0 if (frequency_hz * frame / SAMPLE_RATE) % 1.0 < width else -1.0
            for frame in range(frames)]


def exponential_envelope(frames: int, decay_seconds: float, attack_seconds: float = 0.005) -> list[float]:
    attack_frames = max(1, round(attack_seconds * SAMPLE_RATE))
    return [
        min(1.0, frame / attack_frames) * math.exp(-frame / max(1.0, decay_seconds * SAMPLE_RATE))
        for frame in range(frames)
    ]


def raised_cosine_envelope(frames: int, attack_seconds: float, release_seconds: float) -> list[float]:
    attack = max(1, round(attack_seconds * SAMPLE_RATE))
    release = max(1, round(release_seconds * SAMPLE_RATE))
    result: list[float] = []
    for frame in range(frames):
        if frame < attack:
            result.append(0.5 - 0.5 * math.cos(math.pi * frame / attack))
        elif frame >= frames - release:
            progress = (frames - frame) / release
            result.append(0.5 - 0.5 * math.cos(math.pi * max(0.0, progress)))
        else:
            result.append(1.0)
    return result


def one_pole_lowpass(samples: list[float], cutoff_hz: float) -> list[float]:
    coefficient = math.exp(-math.tau * max(1.0, cutoff_hz) / SAMPLE_RATE)
    previous = 0.0
    result: list[float] = []
    for sample in samples:
        previous = (1.0 - coefficient) * sample + coefficient * previous
        result.append(previous)
    return result


def one_pole_highpass(samples: list[float], cutoff_hz: float) -> list[float]:
    low = one_pole_lowpass(samples, cutoff_hz)
    return [sample - filtered for sample, filtered in zip(samples, low)]


def biquad_modal_resonator(samples: list[float], frequency_hz: float, decay_seconds: float) -> list[float]:
    """A stable second-order resonator driven by ``samples``."""
    radius = math.exp(-1.0 / max(1.0, decay_seconds * SAMPLE_RATE))
    omega = min(math.pi * 0.98, math.tau * max(20.0, frequency_hz) / SAMPLE_RATE)
    coefficient = 2.0 * radius * math.cos(omega)
    first = 0.0
    second = 0.0
    result: list[float] = []
    for sample in samples:
        current = sample + coefficient * first - radius * radius * second
        current = max(-_BOUND, min(_BOUND, current))
        result.append(current)
        second, first = first, current
    return result


def karplus_strong(frequency_hz: float, frames: int, seed: int, damping: float = 0.992) -> list[float]:
    delay = max(2, round(SAMPLE_RATE / max(30.0, frequency_hz)))
    line = seeded_white_noise(delay, seed)
    result: list[float] = []
    index = 0
    for _ in range(frames):
        current = line[index]
        following = line[(index + 1) % delay]
        line[index] = max(-_BOUND, min(_BOUND, damping * 0.5 * (current + following)))
        result.append(current)
        index = (index + 1) % delay
    return result


def reverse(samples: list[float]) -> list[float]:
    return list(reversed(samples))


def bounded_feedback_echo(samples: list[float], delay_seconds: float, feedback: float,
                          repeats: int = 5) -> list[float]:
    delay = max(1, round(delay_seconds * SAMPLE_RATE))
    output = list(samples) + [0.0] * (delay * repeats)
    safe_feedback = max(-0.85, min(0.85, feedback))
    for frame in range(delay, len(output)):
        output[frame] = max(-_BOUND, min(_BOUND, output[frame] + safe_feedback * output[frame - delay]))
    return output


def four_tap_diffusion(samples: list[float], seed: int) -> list[float]:
    delays = (0.011, 0.017, 0.023, 0.031)
    output = list(samples) + [0.0] * round(SAMPLE_RATE * 0.14)
    generator = random.Random(seed)
    for delay_seconds in delays:
        delay = round((delay_seconds + generator.uniform(-0.0005, 0.0005)) * SAMPLE_RATE)
        for frame in range(delay, len(output)):
            output[frame] = max(-_BOUND, min(_BOUND, output[frame] + 0.16 * output[frame - delay]))
    return output


def mono_chorus(samples: list[float], rate_hz: float = 0.33, depth_seconds: float = 0.003) -> list[float]:
    max_delay = round((0.012 + depth_seconds) * SAMPLE_RATE)
    padded = [0.0] * max_delay + samples
    output: list[float] = []
    for frame, sample in enumerate(samples):
        delay = (0.012 + depth_seconds * math.sin(math.tau * rate_hz * frame / SAMPLE_RATE)) * SAMPLE_RATE
        position = max_delay + frame - delay
        lower = int(position)
        fraction = position - lower
        delayed = padded[lower] * (1.0 - fraction) + padded[lower + 1] * fraction
        output.append(max(-_BOUND, min(_BOUND, 0.58 * sample + 0.42 * delayed)))
    return output


def windowed_deterministic_grains(frequency_hz: float, frames: int, seed: int,
                                  grain_seconds: float = 0.045) -> list[float]:
    result = [0.0] * frames
    generator = random.Random(seed)
    grain_frames = max(8, round(grain_seconds * SAMPLE_RATE))
    position = 0
    while position < frames:
        detune = 2.0 ** (generator.uniform(-12.0, 12.0) / 1200.0)
        amplitude = generator.uniform(0.25, 0.75)
        for offset in range(min(grain_frames, frames - position)):
            window = 0.5 - 0.5 * math.cos(math.tau * offset / grain_frames)
            result[position + offset] += amplitude * window * math.sin(
                math.tau * frequency_hz * detune * (position + offset) / SAMPLE_RATE
            )
        position += max(1, round(grain_frames * generator.uniform(0.35, 0.8)))
    return clamp_samples(result)


def _mix(*sources: list[float]) -> list[float]:
    frames = max(len(source) for source in sources)
    return [sum(source[frame] if frame < len(source) else 0.0 for source in sources)
            for frame in range(frames)]


def _scaled(samples: list[float], gain: float) -> list[float]:
    return [sample * gain for sample in samples]


def _tone(frequency_hz: float, frames: int, shape: str = "sine", decay: float = 0.25,
          attack: float = 0.008) -> list[float]:
    oscillators = {
        "sine": sine_oscillator,
        "triangle": triangle_oscillator,
        "pulse": pulse_oscillator,
    }
    source = oscillators[shape](frequency_hz, frames)
    envelope = exponential_envelope(frames, decay, attack)
    return [sample * amount for sample, amount in zip(source, envelope)]


def _impulse(frames: int, seed: int, duration_seconds: float = 0.020) -> list[float]:
    attack_frames = max(1, round(duration_seconds * SAMPLE_RATE))
    noise = seeded_white_noise(attack_frames, seed)
    return [noise[index] * math.exp(-index / max(1, attack_frames / 4)) if index < attack_frames else 0.0
            for index in range(frames)]


def _modal_body(frequency_hz: float, frames: int, seed: int, modes: tuple[float, ...]) -> list[float]:
    excitation = _impulse(frames, seed, 0.012)
    sources = [
        _scaled(biquad_modal_resonator(excitation, frequency_hz * ratio, 0.18 + index * 0.08),
                0.45 / (index + 1))
        for index, ratio in enumerate(modes)
    ]
    return clamp_samples(_mix(*sources))


def _pitched_body(frequency_hz: float, frames: int, seed: int, construction: str) -> list[float]:
    if construction == "analog":
        return _mix(_scaled(_tone(frequency_hz, frames, "triangle", 0.24), 0.65),
                    _scaled(_tone(frequency_hz * 2.0, frames, "sine", 0.12), 0.20))
    if construction == "fm":
        envelope = exponential_envelope(frames, 0.26, 0.006)
        return [math.sin(math.tau * frequency_hz * frame / SAMPLE_RATE +
                         2.3 * math.exp(-frame / 2_800) * math.sin(math.tau * frequency_hz * 2.01 * frame / SAMPLE_RATE))
                * envelope[frame]
                for frame in range(frames)]
    if construction == "pulse":
        return one_pole_lowpass(_tone(frequency_hz, frames, "pulse", 0.13, 0.004), 2_400.0)
    if construction == "string":
        return _mix(_scaled(karplus_strong(frequency_hz, frames, seed, 0.989), 0.42),
                    _scaled(_tone(frequency_hz, frames, "sine", 0.27, 0.006), 0.30))
    if construction == "reed":
        tone = _tone(frequency_hz, frames, "sine", 0.22, 0.020)
        breath = one_pole_highpass(_impulse(frames, seed, 0.045), 900.0)
        return _mix(tone, _scaled(breath, 0.13))
    if construction == "sub":
        body = _mix(_scaled(_tone(frequency_hz * 0.5, frames, "sine", 0.42, 0.080), 0.32),
                    _scaled(_tone(frequency_hz, frames, "sine", 0.24, 0.080), 0.36))
        opening = raised_cosine_envelope(frames, 0.25, 0.18)
        return [sample * amount for sample, amount in zip(body, opening)]
    return _tone(frequency_hz, frames, "sine", 0.23)


def _render(frames: int, samples: list[float], attack: str, default_tail: str) -> tuple[list[float], str, str]:
    return clamp_samples(samples[:frames]), attack, default_tail


def render_analog_ping(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.58)
    body = _pitched_body(midi_to_hz(root_midi), frames, seed, "analog")
    return _render(frames, one_pole_lowpass(body, 3_500.0), "triangle-sine-closing-filter", "tape-echo")


def render_fm_droplet(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.54)
    return _render(frames, _pitched_body(midi_to_hz(root_midi), frames, seed, "fm"), "fm-falling-index", "dark-diffusion")


def render_pulse_pluck(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.44)
    body = _pitched_body(midi_to_hz(root_midi), frames, seed, "pulse")
    return _render(frames, _mix(body, _scaled(_impulse(frames, seed, 0.009), 0.18)), "lowpass-impulse", "short-room")


def render_waveguide_string(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.66)
    return _render(frames, _pitched_body(midi_to_hz(root_midi), frames, seed, "string"), "waveguide-noise-excitation", "dry-damping")


def render_reed_blip(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.46)
    return _render(frames, _pitched_body(midi_to_hz(root_midi), frames, seed, "reed"), "bandpassed-breath-settle", "filtered-breath")


def render_reverse_pluck(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.62)
    body = _pitched_body(midi_to_hz(root_midi), frames, seed, "string")
    swell = reverse(_scaled(_tone(midi_to_hz(root_midi), frames, "triangle", 0.11, 0.005), 0.34))
    return _render(frames, _mix(body, swell), "reverse-triangle-swell", "reverse-bloom")


def render_kalimba_modal(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.52)
    body = _modal_body(midi_to_hz(root_midi), frames, seed, (1.0, 2.71, 4.08))
    return _render(frames, one_pole_lowpass(body, 4_100.0), "damped-thumb-wood", "dry-damping")


def render_ceramic_modal(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.60)
    body = _modal_body(midi_to_hz(root_midi), frames, seed, (1.0, 1.62, 2.37))
    return _render(frames, one_pole_lowpass(body, 3_300.0), "ceramic-damped-impulse", "modal-decay")


def render_felt_key(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.57)
    body = _mix(_scaled(_tone(midi_to_hz(root_midi), frames, "sine", 0.28, 0.024), 0.70),
                _scaled(_pitched_body(midi_to_hz(root_midi), frames, seed, "string"), 0.28))
    return _render(frames, one_pole_lowpass(body, 2_800.0), "felt-hammer", "short-room")


def render_metal_bowl(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.70)
    body = _modal_body(midi_to_hz(root_midi), frames, seed, (1.0, 2.41, 3.87, 5.23))
    return _render(frames, one_pole_lowpass(body, 3_200.0), "damped-metal-impulse", "modal-decay")


def render_glass_reverse(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.63)
    body = _modal_body(midi_to_hz(root_midi), frames, seed, (1.0, 2.76, 5.43))
    return _render(frames, _mix(_scaled(_impulse(frames, seed, 0.006), 0.12), reverse(_scaled(body, 0.65))), "tiny-glass-tap", "reverse-bloom")


def render_chorus_kalimba(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.61)
    body = _modal_body(midi_to_hz(root_midi), frames, seed, (1.0, 2.69, 4.22))
    return _render(frames, mono_chorus(body), "plucked-tine", "chorus-decay")


def render_nylon_waveguide(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.68)
    body = one_pole_lowpass(_pitched_body(midi_to_hz(root_midi), frames, seed, "string"), 2_500.0)
    return _render(frames, body, "nylon-string-excitation", "dark-diffusion")


def render_sub_bloom(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.70)
    return _render(frames, _pitched_body(midi_to_hz(root_midi), frames, seed, "sub"), "sub-sine-slow-open", "dark-diffusion")


def render_filter_ping(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.52)
    ring = biquad_modal_resonator(_impulse(frames, seed, 0.005), midi_to_hz(root_midi), 0.19)
    return _render(frames, one_pole_lowpass(ring, 3_000.0), "resonant-filter-impulse", "tape-echo")


def render_formant_droplet(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.55)
    source = _tone(midi_to_hz(root_midi), frames, "sine", 0.23, 0.008)
    formants = _mix(_scaled(biquad_modal_resonator(source, 700.0, 0.09), 0.27),
                    _scaled(biquad_modal_resonator(source, 1_250.0, 0.07), 0.18))
    return _render(frames, formants, "two-formant-sine-excitation", "short-room")


def render_phase_distortion(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.48)
    frequency = midi_to_hz(root_midi)
    envelope = exponential_envelope(frames, 0.16, 0.004)
    body = [math.sin(math.tau * frequency * frame / SAMPLE_RATE +
                     0.85 * math.exp(-frame / 1_900) * math.sin(math.tau * frequency * frame / SAMPLE_RATE))
            * envelope[frame]
            for frame in range(frames)]
    return _render(frames, body, "phase-index-decay", "dry-damping")


def render_rubber_fm(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.59)
    frequency = midi_to_hz(root_midi)
    envelope = exponential_envelope(frames, 0.25, 0.012)
    body = [math.sin(math.tau * frequency * (1.0 - 0.14 * math.exp(-frame / 3_000)) * frame / SAMPLE_RATE +
                     1.1 * math.exp(-frame / 3_100) * math.sin(math.tau * frequency * 0.5 * frame / SAMPLE_RATE))
            * envelope[frame]
            for frame in range(frames)]
    return _render(frames, body, "downward-fm-pitch-settle", "chorus-decay")


def render_harmonic_stab(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.48)
    frequency = midi_to_hz(root_midi)
    envelope = exponential_envelope(frames, 0.13, 0.030)
    body = [sum(math.sin(math.tau * frequency * harmonic * frame / SAMPLE_RATE) / harmonic
                for harmonic in (1, 2, 3, 5)) * envelope[frame] * 0.48
            for frame in range(frames)]
    return _render(frames, one_pole_lowpass(body, 3_600.0), "slow-bowed-harmonic-onset", "dry-damping")


def render_breath_resonator(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.66)
    breath = one_pole_lowpass(seeded_brown_noise(frames, seed), 1_600.0)
    envelope = exponential_envelope(frames, 0.20, 0.035)
    body = biquad_modal_resonator([value * amount * 0.20 for value, amount in zip(breath, envelope)],
                                  midi_to_hz(root_midi), 0.30)
    return _render(frames, body, "filtered-breath-resonator", "filtered-breath")


def render_modal_glass_cloud(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.70)
    body = _modal_body(midi_to_hz(root_midi), frames, seed, (1.0, 1.98, 3.72))
    return _render(frames, mono_chorus(one_pole_lowpass(body, 3_800.0), 0.18, 0.004), "bowed-modal-partials", "modal-decay")


def render_granular_shimmer(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.69)
    body = one_pole_lowpass(windowed_deterministic_grains(midi_to_hz(root_midi), frames, seed), 4_000.0)
    envelope = raised_cosine_envelope(frames, 0.055, 0.20)
    return _render(frames, [sample * amount * 0.45 for sample, amount in zip(body, envelope)], "windowed-pitched-micrograins", "dark-diffusion")


def render_reverse_glass_unpitched(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.62)
    noise = one_pole_lowpass(seeded_white_noise(frames, seed), 2_600.0)
    envelope = raised_cosine_envelope(frames, 0.30, 0.045)
    body = [sample * amount * 0.23 for sample, amount in zip(reverse(noise), envelope)]
    return _render(frames, body, "reversed-filtered-glass-partials", "reverse-bloom")


def render_dust_impact(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.46)
    dust = one_pole_highpass(_impulse(frames, seed, 0.055), 1_300.0)
    modal = _modal_body(190.0, frames, seed + 1, (1.0, 1.76))
    return _render(frames, _mix(_scaled(dust, 0.18), _scaled(modal, 0.20)), "particulate-under-120ms", "modal-decay")


def render_breath_exhale(root_midi: int, seed: int) -> tuple[list[float], str, str]:
    frames = round(SAMPLE_RATE * 0.64)
    breath = one_pole_lowpass(seeded_brown_noise(frames, seed), 1_100.0)
    envelope = raised_cosine_envelope(frames, 0.045, 0.24)
    formant = biquad_modal_resonator([sample * amount * 0.18 for sample, amount in zip(breath, envelope)],
                                     920.0, 0.16)
    return _render(frames, _mix(_scaled(breath, 0.08), _scaled(formant, 0.38)), "breath-formant-crossfade", "filtered-breath")


AUTHORED_RENDERERS = {
    "analog-ping": render_analog_ping,
    "fm-droplet": render_fm_droplet,
    "pulse-pluck": render_pulse_pluck,
    "waveguide-string": render_waveguide_string,
    "reed-blip": render_reed_blip,
    "reverse-pluck": render_reverse_pluck,
    "kalimba-modal": render_kalimba_modal,
    "ceramic-modal": render_ceramic_modal,
    "felt-key": render_felt_key,
    "metal-bowl-modal": render_metal_bowl,
    "glass-reverse": render_glass_reverse,
    "chorus-kalimba": render_chorus_kalimba,
    "nylon-waveguide": render_nylon_waveguide,
    "sub-bloom": render_sub_bloom,
    "filter-ping": render_filter_ping,
    "formant-droplet": render_formant_droplet,
    "phase-distortion": render_phase_distortion,
    "rubber-fm": render_rubber_fm,
    "harmonic-stab": render_harmonic_stab,
    "breath-resonator": render_breath_resonator,
    "modal-glass-cloud": render_modal_glass_cloud,
    "granular-shimmer": render_granular_shimmer,
    "reverse-glass-unpitched": render_reverse_glass_unpitched,
    "dust-impact": render_dust_impact,
    "breath-exhale": render_breath_exhale,
}


def _tail_frames(samples: list[float], seconds: float) -> list[float]:
    return list(samples) + [0.0] * max(0, round(seconds * SAMPLE_RATE) - len(samples))


def tail_dry_damping(samples: list[float], root_midi: int, seed: int, tail: dict) -> list[float]:
    output = _tail_frames(samples, float(tail.get("durationSeconds", 0.86)))
    return [sample * math.exp(-frame / (SAMPLE_RATE * 0.85)) for frame, sample in enumerate(output)]


def tail_short_room(samples: list[float], root_midi: int, seed: int, tail: dict) -> list[float]:
    output = bounded_feedback_echo(samples, 0.043, 0.34, 7)
    return _tail_frames(one_pole_lowpass(output, 4_600.0), float(tail.get("durationSeconds", 1.05)))


def tail_tape_echo(samples: list[float], root_midi: int, seed: int, tail: dict) -> list[float]:
    output = bounded_feedback_echo(samples, 0.118, 0.43, 9)
    return _tail_frames(one_pole_lowpass(output, 3_100.0), float(tail.get("durationSeconds", 1.75)))


def tail_dark_diffusion(samples: list[float], root_midi: int, seed: int, tail: dict) -> list[float]:
    output = four_tap_diffusion(samples, seed)
    return _tail_frames(one_pole_lowpass(output, 2_700.0), float(tail.get("durationSeconds", 1.20)))


def tail_reverse_bloom(samples: list[float], root_midi: int, seed: int, tail: dict) -> list[float]:
    bloom = reverse(one_pole_lowpass(samples, 3_200.0))
    output = _mix(_scaled(samples, 0.72), _scaled(bloom, 0.24))
    return _tail_frames(output, float(tail.get("durationSeconds", 1.00)))


def tail_chorus_decay(samples: list[float], root_midi: int, seed: int, tail: dict) -> list[float]:
    output = mono_chorus(samples, 0.22 + (seed % 7) * 0.015, 0.0035)
    return _tail_frames(bounded_feedback_echo(output, 0.071, 0.24, 6), float(tail.get("durationSeconds", 1.18)))


def tail_modal_decay(samples: list[float], root_midi: int, seed: int, tail: dict) -> list[float]:
    output = _mix(_scaled(samples, 0.70),
                  _scaled(biquad_modal_resonator(samples, midi_to_hz(root_midi) * 1.91, 0.38), 0.13))
    return _tail_frames(one_pole_lowpass(output, 3_700.0), float(tail.get("durationSeconds", 1.36)))


def tail_filtered_breath(samples: list[float], root_midi: int, seed: int, tail: dict) -> list[float]:
    output = _tail_frames(samples, float(tail.get("durationSeconds", 1.12)))
    noise = one_pole_lowpass(seeded_brown_noise(len(output), seed + 97), 1_250.0)
    return [sample * math.exp(-frame / (SAMPLE_RATE * 0.45)) + noise[frame] * 0.026 * math.exp(-frame / (SAMPLE_RATE * 0.30))
            for frame, sample in enumerate(output)]


TAIL_RENDERERS = {
    "dry-damping": tail_dry_damping,
    "short-room": tail_short_room,
    "tape-echo": tail_tape_echo,
    "dark-diffusion": tail_dark_diffusion,
    "reverse-bloom": tail_reverse_bloom,
    "chorus-decay": tail_chorus_decay,
    "modal-decay": tail_modal_decay,
    "filtered-breath": tail_filtered_breath,
}


def _tail_kind(tail: dict) -> str:
    kind = tail.get("kind", tail.get("topology"))
    if not isinstance(kind, str) or kind not in TAIL_RENDERERS:
        raise ValueError(f"unknown rendered tail topology: {kind!r}")
    return kind


def apply_rendered_tail(samples: list[float], root_midi: int, tail: dict, seed: int) -> list[float]:
    """Apply one bounded offline tail and return deterministic mono samples."""
    kind = _tail_kind(tail)
    return clamp_samples(TAIL_RENDERERS[kind](list(samples), root_midi, seed, tail))


def render_authored(definition: dict, root_midi: int, seed: int) -> RenderedEvent:
    """Render a complete authored event, including its recipe-specific tail."""
    kind = definition.get("kind")
    if not isinstance(kind, str) or kind not in AUTHORED_RENDERERS:
        raise ValueError(f"unknown authored topology: {kind!r}")
    recipe_id = definition.get("id")
    render_root = 60 if isinstance(recipe_id, int) and recipe_id >= 25 else root_midi
    body, default_attack, default_tail = AUTHORED_RENDERERS[kind](render_root, seed)
    tail = definition.get("tail")
    if not isinstance(tail, dict):
        tail = {"kind": definition.get("tailTopology", default_tail)}
    tail_kind = _tail_kind(tail)
    attack = definition.get("attackTopology", default_attack)
    if not isinstance(attack, str):
        raise ValueError("attackTopology must be a string")
    return RenderedEvent(
        samples=apply_rendered_tail(body, render_root, tail, seed),
        topology=kind,
        attack_topology=attack,
        tail_topology=tail_kind,
    )
