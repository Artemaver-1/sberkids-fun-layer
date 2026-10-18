# HANDOFF — контекст для следующей сессии Claude

> Вставь новому Claude: «Прочитай HANDOFF.md и README.md в этом репозитории и продолжай работу».

## Кто и что

- Хакатон **HSE × Sber Mobile Hack 2026**, команда на треке **A «Приколы»** (СберKids — детский банк, 6–13 лет).
- ТЗ: https://kids.hackathon.aam.run (вкладки tracks, limits, score, dod, delivery, materials, faq).
- **Сроки 18.10.2026:** 14:00 стоп-кодинг; 14:00–15:00 ссылка на публичный репозиторий в общую таблицу (https://docs.google.com/spreadsheets/d/1citg00WesqXX21FukhZUDgMMQGMNAL6usle9Afi6r8o) + презентация в Google-форму (pptx/PDF, ≤ 5 мин); 15:00 защиты. Без репозитория, презентации и живого демо работа не оценивается.
- Оценка: виральность 30, бриф/ограничения 25, реализуемость 25 (без бэкенда, текущий стек, обе платформы, без новых разрешений/библиотек), управляемость контентом 10 (CDN), подача 10. Плюс — педагогика.
- Пользователь хочет максимальный балл и реальное внедрение, пишет по-русски, просит делать всё до конца без лишних вопросов.

## Идея (решение)

Слой пасхалок поверх приложения. 5 секретов, найдено «N из 5». Каждая находка → короткий эффект поверх интерфейса → тост «Пасхалка найдена! 1 из 5» → шторка с коллекцией и загадкой-подсказкой к следующей (2 уровня: загадка → «Ещё подсказка»).

| # | Пасхалка | Экран | Триггер |
|---|----------|-------|---------|
| 1 | Мыльные пузыри (12 крупных, можно лопать, 5 % «золотые») | Главный | тряска |
| 2 | Обезьянка-паркурщик (Lottie: бег → прыжок от края экрана → сальто → ловит банан) | Контент | потянуть ленту вниз и держать 0,5 с |
| 3 | Призраки в тумане (смотрят на палец, тают от касания) | Профиль | зажать аватарку 5 с (`hold`, `HoldDetector`; приложение шлёт `reportHold` из long-press на аватарке). Первая секунда — тишина, потом туман с глазками у пальца и «тук» каждую секунду. Ладонь, «экраном вниз», спираль и круги убраны из конфигов |
| 4 | Цех роботов (интерфейс отъезжает, внутри трёхэтажный цех; робот жмёт красную кнопку — интерфейс влетает обратно с ударом) | Настройки | 7 тапов по «Версия приложения» |
| 5 | не будет — всего 4 секрета (`announcedTotal: 4`) | — | — |

Тизер: на главном всплывает один пузырёк → «Потряси телефон!». Шеринг картинкой без ссылок.

## Состояние (всё работает на iPhone 14 пользователя)

- `ios/FunLayerCore` — ядро на Swift (только Foundation): конфиг + валидатор с лимитами, детекторы (Shake, PullHold, Hold, TapSequence, Spiral/Circles, Palm, FaceDownFlip), EggEngine, физика (ParticleField, GhostField). **37 тестов проходят**:
  ```bash
  cd ios/FunLayerCore && F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks; L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib; DEVELOPER_DIR=/Library/Developer/CommandLineTools swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L
  ```
- Шторка «Это пасхалка!» по макету пользователя: робот-маскот с сердечком, сундук со звездой, глянцевые шарики-слоты — всё нарисовано кодом в `FunLayerUI.swift` (`RobotMascot`, `TreasureChest`, `GlossyOrb`), без картинок. Пузыри — `bubble()` в `tools/gen_assets.py`: прозрачный центр, переливы плёнки у края по Френелю, двойное доменное искажение шума.
- `ios/SberKidsFun` — приложение (Swift 6 strict, iOS 15+, Lottie через SPM `lottie-spm`):
  - `FunLayer/` — модуль: окно-оверлей с пропуском касаний, рендеринг (Canvas + Lottie), датчики, тост, шторка, шеринг, звук, загрузка конфига с CDN (sha256, атомарная активация, ETag).
  - `Shell/` — оболочка СберKids **1:1 из экспорта Figma** (картинки экранов + зоны нажатия). Нарезка: `python3 tools/build_shell_assets.py ~/Downloads/sberkids-figma` → `ShellAssets/`.
  - `FunLayerDefaults/` — встроенные копии CDN + `funlayer-manifest.json` (sha256 исходников, т. к. Xcode пережимает PNG).
- `cdn/fun-layer/v1/` — 4 конфига (осень, зима, праздник, рубильник) и ассеты. Публикуются на GitHub Pages workflow `.github/workflows/pages.yml`.
- `android/funlayer-core` — Kotlin-порт ядра (не компилировался — нет Kotlin на машине).
- `tools/` — `gen_assets.py` (пузыри, туман, снежинка, звуки — всё синтезируется), `make_monkey_lottie.py` (обезьяна-кукла на костях, стиль «мягкой 3D-игрушки»), `build_cdn.py` (sha256 + копия в сборку), `build_shell_assets.py`.
- `docs/` — ARCHITECTURE, CONFIG, ANDROID_PORTING, PEDAGOGY (+ модель вероятностей), DEMO (сценарий защиты).

## Сборка и запуск на iPhone

```bash
cd ios
xcodebuild -project SberKidsFun.xcodeproj -scheme SberKidsFun -destination 'generic/platform=iOS' -derivedDataPath /tmp/skf-dd -allowProvisioningUpdates build
xcrun devicectl list devices
xcrun devicectl device install app --device <UDID> /tmp/skf-dd/Build/Products/Debug-iphoneos/SberKidsFun.app
xcrun devicectl device process launch --console --terminate-existing --device <UDID> ru.hackathon.sberkids.funlayer -- -funForce monkey
```

- Команда подписи — Personal Team пользователя (DEVELOPMENT_TEAM в pbxproj). На новой машине/аккаунте выбрать команду в Xcode → Signing & Capabilities.
- Аргументы запуска (передаются **только с `--console`**): `-funForce bubbles|monkey|ghosts|robots`, `-funHold profile.avatar`, `-funReset`, `-funPreset config-winter`, `-tab main|content|piggy|tasks`, `-push profile|history|…`, `-settings`.
- Скриншот: `xcrun devicectl device capture screenshot --device <UDID> --destination x.png` (первые секунды после запуска бывает старый снимок — ждать ~9 с; запись экрана недоступна).
- Лог `[FunLayer] …` с таймингами (`+N ms`) — только в Debug.
- Скрытое меню: Профиль → вкладка «Настройки» → долгое нажатие на «Версия приложения» внизу.

## Грабли, которые уже решены

- Lottie: у последнего ключа не должно быть `i/o`; при сжатии ключей сохранять границы постоянных участков (иначе «расползаются» скачки).
- SwiftUI-геометрия в ScrollView на iOS 27 не приходит при прокрутке → перетяг читается KVO на `UIScrollView.contentOffset` (`PullReader`). При удержании палец неподвижен → слой сам «тикает».
- Ладонь iOS видит как одно касание радиусом 36–60 pt и часто отменяет (palm rejection); «экраном вниз» неочевидно; круги/спираль ненадёжны → призраки — удержание аватарки 5 с.
- Lottie через SwiftUI (`UIViewRepresentable`) вставлялась на 2–3,5 с позже, пока палец держал ленту, и страховочный таймер обрывал обезьяну в воздухе → персонажи теперь в UIKit-слое `lottieStage` под SwiftUI-оверлеем, старт в ту же миллисекунду. Сцена роботов стартует по `onAppear` панели-снимка.
- UI-тесты `ios/SberKidsFunUITests` гоняют реальные жесты на iPhone (`press(forDuration:)`, `press(…thenDragTo:…thenHoldForDuration:)`); `-funHold profile.avatar` — имитация удержания аргументом запуска.
- Датчик приближения на iPhone гасит экран — не используем; датчика света в публичном API нет.
- Figma MCP недоступен (у пользователя view-seat, лимит 6 вызовов/мес) — работали с экспортом PNG 2x.

## Что осталось

1. **Публикация:** публичный репозиторий на GitHub → push → Settings → Pages → Source: GitHub Actions → ссылку в таблицу. В меню разработчика вписать URL `https://<login>.github.io/<repo>/fun-layer/v1/config.json` (и при желании заменить `DebugScreen.defaultURL`).
2. **Презентация** (≤ 5 мин; вопросы: аудитория, инсайт, как решает, механика, преимущества; показать управление через CDN на нескольких кейсах; назвать вес ресурсов; технологии на обеих платформах).
3. Сцена роботов — `tools/make_robots_lottie.py` → `robots.json`; звук `factory.wav`/`slam.wav` в `gen_assets.py`. Сдвиг интерфейса — `RevealSpec` (ядро) + `EffectRuntime.revealOffset` + `RevealPanel` (снимок окна приложения).
4. Можно связать с экраном «Дизайн → Без шуток» в макете: если ребёнок выбрал «без шуток», слой выключается.
5. Проверить звуки на слух (синтезированы, громкость проверена численно).
