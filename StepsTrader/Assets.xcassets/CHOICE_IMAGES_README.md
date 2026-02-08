# How to add images for Gallery activities

Пользователи выбирают картинку для занятия в редакторе (Edit → категория → Add / Edit). Список доступных картинок задаётся в коде.

## 1. Добавить имя в каталог

Открой **StepsTrader/Models/GalleryImageCatalog.swift**. В массив нужной категории (`activity`, `rest`, `joys`) добавь **имя** будущего Image Set, например:

```swift
static let activity: [String] = [
    "activity_favourite_sport",
    // ...
    "activity_yoga",        // новое
    "activity_swimming",    // новое
]
```

Имя должно **совпадать** с именем Image Set в Assets.

## 2. Добавить картинку в Assets

1. В Xcode: **StepsTrader → Assets.xcassets**.
2. Правая кнопка в списке слева → **New Image Set**.
3. Назови Image Set **точно так же**, как строка в каталоге (например `activity_yoga`).
4. Перетащи картинку (PNG/JPG) в слот **1x** (или укажи файл в Contents.json).
5. Рекомендуется: квадрат или 1:1, минимум ~200×200 pt для чёткого @2x.

После этого картинка появится в выборе в приложении (секция «Image» в редакторе занятия). Если картинки с таким именем ещё нет в Assets, в сетке будет плейсхолдер (иконка фото).

## 3. Где что лежит

- **Каталог имён** (какие картинки показывать): **StepsTrader/Models/GalleryImageCatalog.swift**
- **Список опций** (id, titleEn, titleRu): **StepsTrader/Models/DailyEnergy.swift**
- **Редактор** (выбор картинки/иконки): **StepsTrader/Views/CustomActivityEditorView.swift**

---

## Иконки щитов (экран Shields)

Иконки шаблонов щитов (Instagram, TikTok и т.д.) берутся из **TargetResolver**: маппинг bundleId → имя ассета в **StepsTrader/TargetResolver.swift** (`bundleToImageName`). Загрузка пробует имя как есть, затем lowercase и capitalized, поэтому в Assets имя Image Set может быть `instagram`, `Instagram` и т.п.

**Чтобы новая картинка появилась на экране Shields:**  
1. Добавь Image Set в Assets с именем, например, `mynetwork`.  
2. В **TargetResolver.swift** добавь в `bundleToImageName` запись, например: `"com.example.app": "mynetwork"`, и при необходимости в `bundleToDisplayName`, `targetToBundleId`, `targetToScheme`.  
3. В **AppsPageSimplified.swift** добавь этот bundleId в массив `bundleIds` внутри `allTemplates` (рядом с instagram, tiktok и т.д.), чтобы шаблон появился в выборе при создании щита.
