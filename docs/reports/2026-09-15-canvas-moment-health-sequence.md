# Canvas onboarding: объяснение colors перед Health

## Последовательность

1. После подтверждённого сохранения happening и закрытия палитры появляется отдельный `momentResult`: `You already have {availableBalance} colors.` / `By adding happenings, you can get up to {happeningsMaxPoints} colors a day.` Кнопка Next.
2. Next переводит на `balance`: `Pull it down.` / `To see where the other {stepsMaxPoints + sleepMaxPoints} colors can come from. You can also tap the handle.` Пользователь сам раскрывает настоящую панель.
3. Фактическое раскрытие панели переводит на Health: `Activity and Sleep` / `Apple Health data can add up to {max} colors each for Steps and Sleep a day.` При разных лимитах значения показываются отдельно. Connect Health — основная кнопка, Later — контурная.
4. На следующем экране результат запроса или откладывания и напоминание, что Health access можно изменить в Settings.

Все значения читаются из существующей модели/`HappeningDefaults`/`EnergyDefaults`. Показанный баланс — доступные colors, а не обещание, что все они начислены последним happening. Лимиты — дневные максимумы; начисления не изменены.

## Guards и совместимость

- Повторный callback сохранения не меняет entryID. Подтверждение показывается после dismiss палитры.
- `momentResult` принимает только `momentAcknowledged`. Раскрытие панели до Next не продвигает шаг; ручка временно выключена, баланс остаётся читаемым.
- Повторный Next не раскрывает drawer и не выполняет пользовательскую операцию. На следующем шаге ожидается `dataPanelExpanded`.
- Ветка Use this day проходит через то же подтверждение без создания записи.
- Flow version — 2. Сохранённые сеансы v1 читаются; старый Balance при восстановлении переводится на новый `momentResult`. Остальные позиции сохраняются. Resume Health по-прежнему требует пользовательского раскрытия панели.
- Для Health уменьшены вертикальные отступы карточки до 12 pt; горизонтальные остаются 20 pt. Основные действия закреплены вне прокручиваемого пояснения.
- First-run и Release не переключаются на новый сценарий.

## Проверка

- QA iPhone SE 3 / iOS 26.3: 19 coordinator tests и 6 UI tests прошли без ошибок, `/tmp/nowhere-tour-moment-sequence.xcresult`.
- Дополнительные проверки совместимости v1 и Next/ручки при максимальном accessibility-размере: 1 coordinator test и 1 UI test прошли, `/tmp/nowhere-tour-moment-accessibility.xcresult`.
- После просмотра скриншота объяснение Health сокращено до двух строк: ранняя версия с тремя строками требовала прокрутки на SE. Финальный полный маршрут прошёл без ошибок: 1 UI test, `/tmp/nowhere-tour-moment-final.xcresult`. Дополнительная проверка подтверждает отсутствие text scroll на Health при обычном размере текста; весь текст и обе кнопки видны на скриншоте.
- Проверены tap/drag drawer, Later → checklist → Finish, отмена Share, промах → подтверждение → продолжение, возврат из вложенных setup-страниц, Restart/Stop.
- Физические Health/Screen Time/Apple auth и обновление установки на телефон здесь не выполнялись. В симуляторе эти ветки не объявляются проверенными на устройстве.
- Два полных прогона используют реальное сохранение: QA-симулятор получает два новых happenings и 12 colors, без создания групп и списаний. Остальные маршруты используют существующий день. История не удаляется ради повторного запуска.

## Скриншоты SE, финальная версия

- [Подтверждение colors и Next](canvas-moment-health-sequence/moment-result-se.png)
- [Pull it down и настоящая ручка](canvas-moment-health-sequence/pull-down-se.png)
- [Activity and Sleep, Connect Health и Later](canvas-moment-health-sequence/health-se.png)
