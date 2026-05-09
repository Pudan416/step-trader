#!/usr/bin/env python3
"""
Add Russian localizations for `option.description.<id>` and `option.examples.<id>`
keys in `StepsTrader/Localizable.xcstrings`.

The English values were seeded by `add_option_localizations.py`. This sister
script fills in the corresponding `ru` slots.

Idempotent: skips entries that already have a `ru` localization.
"""
from __future__ import annotations

import json
from collections import OrderedDict
from pathlib import Path

XCSTRINGS_PATH = Path(__file__).resolve().parent.parent / "StepsTrader" / "Localizable.xcstrings"

# (id, description_ru, examples_ru)
RU_TRANSLATIONS: list[tuple[str, str, str]] = [
    # Body
    ("body_walking",
     "Двигаться вперёд телом по миру.",
     "прогулка по городу, прогулка на природе, ходьба без цели"),
    ("body_physical_effort",
     "Использовать силу и сопротивление.",
     "спортзал, домашняя тренировка, физический труд"),
    ("body_stretching",
     "Раскрытие и снятие напряжения.",
     "растяжка, йога, мобильность, медленная разминка"),
    ("body_resting",
     "Позволить телу восстановиться.",
     "хороший сон, лёжа, осознанный перерыв, короткий сон"),
    ("body_breathing",
     "Возвращение к физическому ритму.",
     "пауза для дыхания, успокаивающее дыхание, осознанный вдох"),
    ("body_touch",
     "Чувствовать мир через контакт.",
     "вода, трава, солнечный свет, физическое заземление"),
    ("body_balance",
     "Найти равновесие и координацию.",
     "йога, упражнения на баланс, стояние на одной ноге, тайчи"),
    ("body_repetition",
     "Делать простые физические действия с присутствием.",
     "уборка, наведение порядка, повседневные ритуалы"),
    ("body_warming",
     "Чувствовать тепло и комфорт в теле.",
     "горячий душ, пребывание на солнце, тёплый напиток"),
    ("body_stillness",
     "Быть полностью неподвижным на мгновение.",
     "тихое сидение, сканирование тела, безмолвная пауза"),
    ("body_healing",
     "Заботиться о теле через медицинское внимание.",
     "визит к врачу, приём лекарств, терапия, антидепрессанты"),
    # Mind
    ("mind_focusing",
     "Удерживать внимание на одном.",
     "чтение, глубокая работа, внимательное слушание"),
    ("mind_learning",
     "Принимать новое в ум.",
     "учёба, образовательный контент, отработка навыка"),
    ("mind_thinking",
     "Активная обработка идей или ситуаций.",
     "размышление, решение задач, мысленное исследование"),
    ("mind_planning",
     "Организовать то, что будет дальше.",
     "структурирование задач, расстановка приоритетов, поиск работы"),
    ("mind_writing",
     "Превращать мысли в форму.",
     "ведение дневника, заметки, наброски идей"),
    ("mind_observing",
     "Замечать, не вмешиваясь.",
     "наблюдение за людьми, замечание паттернов, осознанность"),
    ("mind_questioning",
     "Подвергать сомнению предположения.",
     "вопросы «почему», переосмысление, моменты любопытства"),
    ("mind_ordering",
     "Создавать ясность и структуру.",
     "организация файлов, упрощение, упорядочивание идей"),
    ("mind_remembering",
     "Сознательное возвращение к прошлому моменту.",
     "сидение на скамейке, обзор дня, воспоминание"),
    ("mind_letting_go",
     "Отпустить умственное напряжение.",
     "закрытие задач, прекращение перебора мыслей, пауза"),
    # Heart
    ("heart_joy",
     "Чувствовать лёгкость и тепло.",
     "смех, игривые моменты, спонтанное счастье"),
    ("heart_calm",
     "Чувствовать себя устойчиво и в безопасности внутри.",
     "тихое время, расслабление, эмоциональная лёгкость"),
    ("heart_gratitude",
     "Признать что-то ценным.",
     "благодарность за момент, чувство признательности"),
    ("heart_connection",
     "Чувствовать близость к кому-то.",
     "значимый разговор, общее молчание"),
    ("heart_care",
     "Дарить внимание и тепло.",
     "помогать, поддерживать, заботиться о себе"),
    ("heart_wonder",
     "Чувствовать восхищение или любопытство.",
     "замечать красоту, удивление, вдохновение"),
    ("heart_trust",
     "Позволять открытость без напряжения.",
     "положиться на кого-то, эмоциональная безопасность"),
    ("heart_vulnerability",
     "Позволить себе чувствовать честно.",
     "эмоциональная открытость, искренний разговор"),
    ("heart_belonging",
     "Чувствовать себя частью чего-то.",
     "сообщество, общая идентичность, чувство дома"),
    ("heart_peace",
     "Глубокая внутренняя тишина.",
     "принятие себя, эмоциональная неподвижность"),
]


def add_ru(entry: dict, value: str) -> bool:
    """Add a `ru` localization to an existing xcstrings entry. Returns True if added."""
    locs = entry.setdefault("localizations", OrderedDict())
    if "ru" in locs:
        return False
    locs["ru"] = {"stringUnit": {"state": "translated", "value": value}}
    return True


def main() -> int:
    with XCSTRINGS_PATH.open("r", encoding="utf-8") as fp:
        data = json.load(fp, object_pairs_hook=OrderedDict)

    strings: "OrderedDict[str, dict]" = data["strings"]
    added = 0
    skipped = 0
    missing: list[str] = []

    for opt_id, desc_ru, examples_ru in RU_TRANSLATIONS:
        for key, ru_value in (
            (f"option.description.{opt_id}", desc_ru),
            (f"option.examples.{opt_id}", examples_ru),
        ):
            entry = strings.get(key)
            if entry is None:
                missing.append(key)
                continue
            if add_ru(entry, ru_value):
                added += 1
            else:
                skipped += 1

    with XCSTRINGS_PATH.open("w", encoding="utf-8") as fp:
        json.dump(data, fp, ensure_ascii=False, indent=2, separators=(",", " : "))
        fp.write("\n")

    print(f"added={added} skipped={skipped} missing={len(missing)}")
    if missing:
        print("Missing keys:", missing)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
