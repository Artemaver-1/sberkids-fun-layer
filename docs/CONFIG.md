# Формат конфига `kids_fun_layer`

Один JSON на обе платформы. Все поля необязательны — отсутствующее получает значение по умолчанию, неизвестное игнорируется. Пути ресурсов относительные: разрешаются от адреса самого конфига, поэтому один и тот же файл работает на любом CDN.

```jsonc
{
  "schemaVersion": 1,            // версия формата; больше поддерживаемой — конфиг отклоняется
  "configId": "autumn-2026",     // для отладки и аналитики контента
  "enabled": true,               // рубильник: false — слой выключен без релиза
  "announcedTotal": 5,           // сколько секретов «объявлено» (слоты с замочком)
  "foundSound": "chime",         // звук находки (ключ из assets)
  "texts": { … },                // все тексты; {n}, {total}, {left} подставляются
  "teaser": { … },               // подсказка к самой первой пасхалке
  "eggs": [ … ],                 // пасхалки
  "assets": { "key": { "url": "assets/bubble.png", "sha256": "…", "bytes": 133963 } }
}
```

## Пасхалка

```jsonc
{
  "id": "bubbles",
  "order": 1,                         // порядок в цепочке подсказок
  "enabled": true,
  "title": "Мыльные пузыри",
  "pictogram": "egg.bubbles",         // иконка в коллекции: egg.bubbles | egg.monkey | egg.ghosts | egg.snow
  "screen": "main",                   // main | piggy | tasks | content | profile (денежные экраны запрещены в коде)
  "trigger": { "type": "shake", "threshold": 1.3, "peaks": 3, "windowMs": 1000 },
  "fallbackTrigger": null,            // второй способ вызвать (например, для устройств без мультитача)
  "schedule": { "from": "2026-12-15", "to": "2027-01-10", "months": [12, 1] },
  "cooldownMs": 3000,
  "variants": [ { "id": "rainbow", "weight": 95, "effect": { … } } ],
  "hint": {                           // как найти ЭТУ пасхалку (показывается после предыдущей)
    "riddle": "Пузыри любят, когда их трясут!…",
    "help": "Открой «Главный» и потряси телефон три раза.",
    "pictograms": ["tab.main", "gesture.shake"]
  }
}
```

### Триггеры

| type | Параметры | По умолчанию |
|------|-----------|--------------|
| `shake` | `threshold` (g, 0.6–4), `peaks` (1–8), `windowMs` | 1.3 g, 3 пика, 1000 мс |
| `pullHold` | `distance` (pt, 40–250), `holdMs` | 90 pt, 1000 мс |
| `palm` | `minTouches` (2–10), `minRadius` (pt), `holdMs`, `maxMovement`, `maxHoldMs` | 3, 30 pt, 1200 мс, 70 pt, 6000 мс |
| `faceDownFlip` | `downMs` | 800 мс |
| `circles` | `minTurns`, `minDiameter`, `minDurationMs`, `maxDurationMs`, `consistency` | 1,9 оборота, 100 pt, 500–4000 мс, вращение в одну сторону ≥ 85 % |
| `spiral` | `minTurns` (1,5–5), `minDiameter` (pt), `minDurationMs`, `maxDurationMs` | 2 витка, 120 pt, 600–4000 мс; плюс вращение в одну сторону ≥ 85 % и смена радиуса ≥ 35 % |
| `tapSequence` | `target` (элемент, о нажатиях на который сообщает приложение), `taps` (2–15), `maxGapMs` | `settings.version`, 7, 800 мс |

### Эффект

```jsonc
{
  "durationMs": 7000,            // 1000–10000
  "dim": { "color": "#140F33", "opacity": 0.3 },   // ≤ 0.35
  "sound": "jungle",             // при старте
  "interactSound": "pop",        // при касании пузыря/призрака
  "haptic": "light",             // none | light | medium | success
  "layers": [ … ],               // рисуются по порядку
  "reveal": {                    // необязательно: интерфейс отъезжает и открывает сцену
    "direction": "right",        // right | left
    "openMs": 1100,              // механическое открытие (рывок, фиксатор, сервопривод)
    "closeAtMs": 5750,           // когда возвращается (момент нажатия кнопки в сцене)
    "closeMs": 280               // как быстро влетает обратно; затем удар о край и тряска
  }
}
```

### Слои

| type | Поля |
|------|------|
| `particles` | `asset`, `count` (≤ 40), `sizeMin/Max`, `speedMin/Max`, `direction` (`up`/`down`), `wobble`, `wobbleSpeed`, `spin` (0 — блик не вращается), `spawnMs`, `tapToPop`, `opacity` |
| `lottie` | `asset`, `speed` (0.25–3), `placement` (`fullscreen`) |
| `fog` | `asset` (бесшовная текстура), `colors` (до 4), `opacity`, `drift`, `stars` (≤ 60) |
| `ghosts` | `count` (≤ 6), `sizeMin/Max`, `palette`, `tapToVanish`, `followFinger` |

Из этих четырёх примитивов собираются новые пасхалки без разработки: снегопад, листопад, конфетти, светлячки, новый Lottie-персонаж, «северное сияние» из тумана и звёзд.

### Пиктограммы подсказок

`tab.main`, `tab.content`, `tab.piggy`, `tab.tasks`, `screen.profile`, `gesture.shake`, `gesture.pullHold`, `gesture.palm` — анимированные иконки, понятные до чтения текста.

## Тизер

```json
{ "enabled": true, "screen": "main", "eggId": "bubbles", "delayMs": 5000, "maxShows": 3, "text": "Потряси телефон!" }
```

Пока первая пасхалка не найдена, на главном экране не больше 3 раз всплывает один пузырёк. Тап — он лопается и показывает «Потряси телефон!». Так первую пасхалку находят все, остальные — по загадкам.

## Что проверяет валидатор

- версия схемы, рубильник;
- экран разрешён приложением и не денежный;
- ресурсы — только https (или относительные от https-конфига), суммарно ≤ 6 МБ, у каждого sha256;
- все числа зажаты в безопасные диапазоны;
- в тексте шаринга нет ссылок;
- неизвестные слои/триггеры отбрасываются точечно с предупреждением (видно в меню разработчика).
