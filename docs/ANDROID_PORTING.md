# Перенос на Android

Код механики пишется дважды — так устроен СберKids (два нативных приложения). Поэтому всё, что можно, вынесено в платформенно-независимое ядро, а платформенный код сведён к рисованию и датчикам.

## Что уже перенесено

`android/funlayer-core/` — Kotlin-версия ядра, построчно повторяющая `ios/FunLayerCore`:

| Swift | Kotlin | Что внутри |
|-------|--------|------------|
| `ConfigDTO.swift`, `Model.swift`, `ConfigValidator.swift` | `Config.kt` | разбор JSON (org.json из Android SDK), те же лимиты и правила |
| `Detectors.swift` | `Detectors.kt` | тряска, удержание ленты, ладонь, переворот |
| `EggEngine.swift`, `Progress.swift` | `Engine.kt` | выбор пасхалки, кулдаун, веса, прогресс, подсказки, SplitMix64 |
| `Simulation.swift` | `Simulation.kt` | физика пузырей, капель, призраков, огибающая |

Зависимостей нет. Последовательность `SeededRandom` совпадает с iOS — одинаковые тесты дают одинаковый результат.

## Соответствие платформенного кода

| iOS | Android |
|-----|---------|
| `OverlayWindow` (отдельный `UIWindow`, `hitTest` → `nil`) | `Box(Modifier.fillMaxSize())` поверх `NavHost` в корневом `setContent`; `pointerInput` пропускает событие, если не попали в пузырь (`awaitPointerEventScope`, без `consume()`) |
| `CMMotionManager.deviceMotion` (userAcceleration, gravity) | `SensorManager` + `TYPE_LINEAR_ACCELERATION` и `TYPE_GRAVITY`, `SENSOR_DELAY_GAME`; регистрируются в `DisposableEffect` только на нужном экране |
| `PalmGestureRecognizer` на окне | `Activity.dispatchTouchEvent`: `MotionEvent.pointerCount`, `getTouchMajor(i)`; при `ARMED` — `ACTION_CANCEL` дочерним вью, чтобы ладонь не нажала кнопку |
| SwiftUI `Canvas` + `TimelineView(.animation)` | Compose `Canvas` + `LaunchedEffect { while(true) withFrameNanos { … } }` |
| `GraphicsContext.draw(image)` | `DrawScope.drawImage` / `withTransform { rotate; scale }` |
| `LottieAnimationView` | `LottieAnimation(LottieCompositionSpec.File(path))` — Lottie уже в стеке |
| `AVAudioPlayer` (.ambient) | `SoundPool` (уже есть в приложении) |
| `UIImpactFeedbackGenerator` | `HapticFeedbackConstants` / `Vibrator` (уже есть) |
| `UserDefaults` | `DataStore` / `SharedPreferences` (интерфейс `KeyValueStore`) |
| `URLSession` + sha256 (`CryptoKit`) | существующий сетевой слой приложения + `MessageDigest("SHA-256")` |
| `UIActivityViewController` | `Intent.ACTION_SEND` с картинкой через `FileProvider` |

## Датчики на Android

Призраки вызываются переворотом «экраном вниз» — нужен только акселерометр, он есть в любом телефоне. `TYPE_GRAVITY` — программный датчик поверх акселерометра; если его нет (очень дешёвые модели без гироскопа), гравитация берётся низкочастотным фильтром из `TYPE_ACCELEROMETER`. Датчики света и приближения не используются — их наличие и качество на Android не гарантированы.

## Разрешения

Никаких. Акселерометр, гравитация и касания на Android разрешений не требуют. Bluetooth, камера, микрофон и геолокация не используются.

## Единицы

- Касания: `getTouchMajor()` в пикселях → делим на 2 и на `density`, получаем радиус в dp ≈ pt на iOS.
- Ускорение: Android отдаёт м/с², ядро ждёт g — делим на 9,81.
- Гравитация: на Android экран вверх даёт `z ≈ +9,81`, на iOS `gravity.z ≈ −1`. Передаём в ядро `−z / 9,81`.

## Объём

Ядро — готово. Платформенная часть Android — около 600 строк Compose (оверлей, 4 рендерера, датчики, тост, шторка). По опыту iOS-прототипа — 5–6 рабочих дней с тестированием на Android 8–15.
