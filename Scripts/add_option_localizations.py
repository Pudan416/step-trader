#!/usr/bin/env python3
"""
One-shot script: inject `option.title.<id>`, `option.description.<id>`, and
`option.examples.<id>` keys into `StepsTrader/Localizable.xcstrings`.

Titles get en + ru. Descriptions / examples get en only (Russian translations
are pending — see TODO in `Models/DailyEnergy.swift`).

Idempotent: skips keys that already exist.
"""
from __future__ import annotations

import json
from collections import OrderedDict
from pathlib import Path

XCSTRINGS_PATH = Path(__file__).resolve().parent.parent / "StepsTrader" / "Localizable.xcstrings"

# (id, titleEn, titleRu, description, examples)
OPTIONS: list[tuple[str, str, str, str, str]] = [
    # Body
    ("body_walking", "Walking", "Ходьба",
     "Moving forward with your body in the world.",
     "city walk, nature walk, walking without a goal"),
    ("body_physical_effort", "Physical Effort", "Физическое усилие",
     "Using strength and resistance.",
     "gym, home workout, manual work"),
    ("body_stretching", "Stretching", "Растяжка",
     "Opening and releasing tension.",
     "stretching, yoga, mobility, slow warm-up"),
    ("body_resting", "Resting", "Отдых",
     "Allowing the body to recover.",
     "good sleep, lying down, intentional break, power nap"),
    ("body_breathing", "Breathing", "Дыхание",
     "Returning to your physical rhythm.",
     "breathing pause, calming breath, mindful inhale"),
    ("body_touch", "Touch", "Прикосновение",
     "Feeling the world through contact.",
     "water, grass, sunlight, physical grounding"),
    ("body_balance", "Balance", "Баланс",
     "Finding equilibrium and coordination.",
     "yoga, balance exercises, standing on one leg, tai chi"),
    ("body_repetition", "Repetition", "Повторение",
     "Doing simple physical actions with presence.",
     "cleaning, tidying, daily routines"),
    ("body_warming", "Warming", "Согревание",
     "Feeling heat and comfort in the body.",
     "hot shower, sun exposure, warm drink"),
    ("body_stillness", "Stillness", "Неподвижность",
     "Being completely motionless for a moment.",
     "sitting quietly, body scan, silent pause"),
    ("body_healing", "Healing", "Исцеление",
     "Taking care of your body through medical attention.",
     "visiting a doctor, taking medication, therapy, antidepressants"),
    # Mind
    ("mind_focusing", "Focusing", "Фокусировка",
     "Holding attention on one thing.",
     "reading, deep work, careful listening"),
    ("mind_learning", "Learning", "Обучение",
     "Taking something new into the mind.",
     "studying, educational content, skill practice"),
    ("mind_thinking", "Thinking", "Размышление",
     "Actively processing ideas or situations.",
     "reflecting, problem-solving, mental exploration"),
    ("mind_planning", "Planning", "Планирование",
     "Organising what comes next.",
     "structuring tasks, setting priorities, looking for a job"),
    ("mind_writing", "Writing", "Письмо",
     "Turning thoughts into form.",
     "journaling, notes, drafting ideas"),
    ("mind_observing", "Observing", "Наблюдение",
     "Noticing without interfering.",
     "watching people, noticing patterns, awareness"),
    ("mind_questioning", "Questioning", "Вопрошание",
     "Challenging assumptions.",
     "asking why, rethinking, curiosity moments"),
    ("mind_ordering", "Ordering", "Упорядочивание",
     "Creating clarity and structure.",
     "organising files, simplifying, arranging ideas"),
    ("mind_remembering", "Remembering", "Воспоминание",
     "Returning to a past moment consciously.",
     "sitting on a bench, reviewing the day, recalling a memory"),
    ("mind_screen_detox", "Screen Detoxing", "Экранный детокс",
     "A day with minimal screen time.",
     "phone untouched, no scrolling, present in the moment"),
    # Heart
    ("heart_joy", "Joy", "Радость",
     "Feeling lightness and warmth.",
     "laughter, playful moments, spontaneous happiness"),
    ("heart_calm", "Calm", "Спокойствие",
     "Feeling settled and safe inside.",
     "quiet time, relaxation, emotional ease"),
    ("heart_gratitude", "Gratitude", "Благодарность",
     "Recognising something as valuable.",
     "appreciating a moment, feeling thankful"),
    ("heart_connection", "Connection", "Связь",
     "Feeling close to someone.",
     "meaningful talk, shared silence"),
    ("heart_care", "Care", "Забота",
     "Giving attention and warmth.",
     "helping, supporting, caring for yourself"),
    ("heart_wonder", "Wonder", "Удивление",
     "Feeling awe or curiosity.",
     "noticing beauty, surprise, inspiration"),
    ("heart_trust", "Trust", "Доверие",
     "Allowing openness without tension.",
     "relying on someone, emotional safety"),
    ("heart_vulnerability", "Vulnerability", "Уязвимость",
     "Allowing yourself to feel honestly.",
     "emotional openness, sincere sharing, fill blue or green"),
    ("heart_belonging", "Belonging", "Принадлежность",
     "Feeling part of something.",
     "community, shared identity, feeling at home"),
    ("heart_peace", "Peace", "Мир",
     "Deep inner quiet.",
     "acceptance of self, emotional stillness"),
]


def make_entry(en: str, ru: str | None) -> dict:
    """xcstrings entry with one or two language localizations."""
    locs: "OrderedDict[str, dict]" = OrderedDict()
    locs["en"] = {"stringUnit": {"state": "translated", "value": en}}
    if ru is not None:
        locs["ru"] = {"stringUnit": {"state": "translated", "value": ru}}
    return {"localizations": locs}


def main() -> int:
    with XCSTRINGS_PATH.open("r", encoding="utf-8") as fp:
        data = json.load(fp, object_pairs_hook=OrderedDict)

    strings: "OrderedDict[str, dict]" = data["strings"]
    added = 0
    skipped = 0

    new_keys: list[tuple[str, dict]] = []
    for opt_id, title_en, title_ru, desc_en, examples_en in OPTIONS:
        for key, en, ru in (
            (f"option.title.{opt_id}", title_en, title_ru),
            (f"option.description.{opt_id}", desc_en, None),
            (f"option.examples.{opt_id}", examples_en, None),
        ):
            if key in strings:
                skipped += 1
                continue
            new_keys.append((key, make_entry(en, ru)))
            added += 1

    # Append new keys at the end — Xcode reorders on save anyway, and we don't
    # want to perturb existing key ordering / risk diff explosion.
    for k, v in new_keys:
        strings[k] = v

    with XCSTRINGS_PATH.open("w", encoding="utf-8") as fp:
        json.dump(data, fp, ensure_ascii=False, indent=2, separators=(",", " : "))
        fp.write("\n")

    print(f"added={added} skipped={skipped} total_strings={len(data['strings'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
