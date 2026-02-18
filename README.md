# Fishing Planet — Xbox Controller Vibration Fix (macOS)

Enables Xbox controller vibration in Fishing Planet on macOS. The game has built-in vibration support but Unity disables it on macOS. This mod hooks into Unity's runtime and redirects vibration commands through Steam Input API, with automatic fallback to direct IOKit HID if Steam Input is unavailable.

**[Русская версия ниже / Russian version below](#ru)**

---

## Requirements

- macOS 13+ (Apple Silicon)
- Fishing Planet via Steam
- Xbox controller connected via Bluetooth

## Installation

### Option A: GUI App (recommended)

```bash
git clone https://github.com/LynxEsq/fishing-planet-vibfix.git
cd fishing-planet-vibfix
make VibFix.app
open VibFix.app
```

The app lets you install/uninstall, configure vibration strength, and switch between English and Russian.

### Option B: Command line

Pre-built binaries are included — no compilation needed.

```bash
git clone https://github.com/LynxEsq/fishing-planet-vibfix.git
cd fishing-planet-vibfix

chmod +x scripts/install.sh scripts/uninstall.sh
./scripts/install.sh
```

The installer automatically configures Steam Launch Options — no manual setup needed. It uses pre-built binaries from `build/`. If they're missing, it will compile from source automatically (requires Xcode Command Line Tools).

### Enable Steam Input (required)

The fix uses Steam's API to vibrate the controller. Without this, vibration won't work.

1. Open Steam
2. Right-click **Fishing Planet** > **Properties**
3. Go to **Controller** tab
4. Set to **Enable Steam Input**

### Verify it works

1. Launch Fishing Planet through Steam
2. **Short test vibration on start** = everything is working correctly
3. Go fishing — you'll feel vibration on bite and during reeling

If there's no test vibration, check `vibfix.log` in the mod directory.

## Configuration

Edit `config.txt` to customize vibration strength (or use the GUI app). Changes apply on next game restart.

```ini
# Values are 0-100 (percentage of motor strength)
#
# Controller motors:
#   left_motor    = low-frequency heavy rumble ("thump")
#   right_motor   = high-frequency light buzz ("whirr")
#   left_trigger  = left trigger motor (Xbox Elite / DualSense only)
#   right_trigger = right trigger motor (Xbox Elite / DualSense only)

# Bite — fish strikes the hook
bite_left_motor = 100
bite_right_motor = 50
bite_left_trigger = 40
bite_right_trigger = 50
bite_double_tap = true
bite_double_tap_strength = 75

# Reeling — pulling the fish in
reel_left_motor = 45
reel_right_motor = 100
reel_left_trigger = 30
reel_right_trigger = 50

# General
test_on_start = true
verbose_log = true
```

## Game updates

The mod uses Steam Launch Options instead of modifying game files. Game updates should not break it.

If vibration stops working after an update, re-run `./scripts/install.sh` or click Install in the GUI app.

## Uninstall

**GUI:** Click "Uninstall" in VibFix.app.

**Command line:**
```bash
./scripts/uninstall.sh
```

Removes Steam Launch Options. Config and dylib are not deleted.

## Building from source

```bash
# Install Xcode Command Line Tools (if not already installed)
xcode-select --install

# Build everything (dylib, launcher, GUI app)
make all

# Or build and copy to build/
chmod +x build.sh
./build.sh
```

## How it works

1. The installer sets Steam Launch Options to use a wrapper binary
2. The wrapper sets `DYLD_INSERT_LIBRARIES` to inject the fix into the game process
3. The fix hooks Unity's IL2CPP runtime:
   - Forces `SystemInfo.supportsVibration` to return `true`
   - Intercepts `NativeInputSystem.IOCTL` to capture vibration commands
4. Vibration output (dual path):
   - **Steam Input API** — primary method, uses Steam's controller subsystem
   - **IOKit HID** — automatic fallback, sends Xbox Bluetooth HID rumble reports directly

Both paths are tried during startup. Steam Input is preferred when available; HID fallback activates instantly if Steam Input is unavailable.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| No test vibration on start | Check `vibfix.log`. Make sure Steam Input is enabled. |
| Controller not detected | Reconnect controller, restart game. Check Steam sees it. |
| Game crashes on start | Run `./scripts/uninstall.sh`, then `./scripts/install.sh`. |
| Vibration feels wrong | Edit `config.txt` — adjust motor percentages. |
| Reeling vibration too weak | This was fixed in v9.0. Update to latest version. |

## Files

| File | Description |
|------|-------------|
| `VibFix.app/` | GUI app — double-click to launch |
| `config.txt` | Vibration settings (user-editable) |
| `scripts/install.sh` | CLI installer — auto-configures Steam Launch Options |
| `scripts/uninstall.sh` | CLI uninstaller — removes Launch Options |
| `build/` | Pre-built binaries (ready to use) |
| `src/` | Source code (VibFixApp.m, vibration_fix.m, launch_wrapper.c) |
| `assets/` | App icon and banner image |
| `Makefile` | Build rules |

## Changelog

### v9.0
- **GUI app** (`VibFix.app`): native macOS installer/configurator with dark Fishing Planet theme, banner, gamepad icon, slider controls, RU/EN language toggle
- **Steam Launch Options**: installer now auto-configures Steam Launch Options (no more binary replacement, no daily re-install needed)
- **New launch wrapper** (`launch_wrapper.c`): resolves `.app` bundle paths, preserves Steam overlay libraries in `DYLD_INSERT_LIBRARIES`
- **Fixed REEL vibration**: normalized lowFreq values from [0, 0.30] to [0, 1.0] — reeling was barely felt before (4-13% instead of 45-100%)
- **Verbose logging**: new `verbose_log` config option — logs every vibration request for debugging
- **HIGH event detection**: detects highFreq-only vibration events (for future game analysis)

### v8.0
- **IOKit HID fallback**: if Steam Input is unavailable, vibration now works via direct Xbox Bluetooth HID reports (same approach as [GRID Autosport vibfix](https://github.com/LynxEsq/grid-autosport-vibfix))
- **Fixed Steam Input initialization**: added `SteamAPI_GetHSteamPipe/User` checks to avoid calling `SteamInput()` before Steam API is ready — this was the root cause of the "SteamInput() returned NULL" issue in v7.0
- **Extended Steam Input retries**: 60 attempts (30 seconds) instead of 10 (5 seconds)
- **IOCTL diagnostic logging**: all Unity IOCTL types are now logged (first 10 + periodic), not just RMBL — helps debug if game stops sending vibration commands
- **Unified rumble output**: `outputRumble()` abstraction routes vibration to whichever backend is available (Steam Input or HID)

### v7.0
- Initial public release
- IL2CPP hooks for `SupportsVibration` and `IOCTL`
- Steam Input API for vibration output
- Configurable bite/reel motor strengths
- Double-tap bite effect

## License

MIT

---

<a name="ru"></a>
# Fishing Planet — Фикс вибрации Xbox-контроллера (macOS)

Включает вибрацию Xbox-контроллера в Fishing Planet на macOS. В игре есть встроенная поддержка вибрации, но Unity отключает её на macOS. Этот мод перехватывает команды вибрации и перенаправляет их через Steam Input API с автоматическим фоллбеком на прямой IOKit HID, если Steam Input недоступен.

## Требования

- macOS 13+ (Apple Silicon)
- Fishing Planet через Steam
- Xbox-контроллер по Bluetooth

## Установка

### Вариант А: GUI-приложение (рекомендуется)

```bash
git clone https://github.com/LynxEsq/fishing-planet-vibfix.git
cd fishing-planet-vibfix
make VibFix.app
open VibFix.app
```

Приложение позволяет установить/удалить мод, настроить силу вибрации и переключить язык (EN/RU).

### Вариант Б: Командная строка

Собранные бинарники уже включены — компиляция не нужна.

```bash
git clone https://github.com/LynxEsq/fishing-planet-vibfix.git
cd fishing-planet-vibfix

chmod +x scripts/install.sh scripts/uninstall.sh
./scripts/install.sh
```

Установщик автоматически настраивает Steam Launch Options — ручная настройка не нужна. Использует готовые бинарники из `build/`. Если их нет — скомпилирует из исходников (нужны Xcode Command Line Tools).

### Включить Steam Input (обязательно)

Фикс использует API Steam для управления вибрацией. Без этого вибрация не будет работать.

1. Откройте Steam
2. ПКМ на **Fishing Planet** > **Свойства**
3. Вкладка **Контроллер**
4. Выберите **Включить Steam Input**

### Проверка работы

1. Запустите Fishing Planet через Steam
2. **Короткая тестовая вибрация при запуске** = всё работает правильно
3. Идите на рыбалку — вибрация при поклёвке и вываживании

Если тестовой вибрации нет — проверьте `vibfix.log` в директории мода.

## Настройка

Редактируйте `config.txt` для настройки силы вибрации (или используйте GUI-приложение). Изменения применяются при следующем запуске игры.

```ini
# Значения 0-100 (процент силы мотора)
#
# Моторы контроллера:
#   left_motor    = низкочастотный тяжёлый мотор ("удар")
#   right_motor   = высокочастотный лёгкий мотор ("жужжание")
#   left_trigger  = мотор левого триггера (только Xbox Elite / DualSense)
#   right_trigger = мотор правого триггера (только Xbox Elite / DualSense)

# Поклёвка — рыба клюнула
bite_left_motor = 100
bite_right_motor = 50
bite_left_trigger = 40
bite_right_trigger = 50
bite_double_tap = true
bite_double_tap_strength = 75

# Вываживание — тянем рыбу
reel_left_motor = 45
reel_right_motor = 100
reel_left_trigger = 30
reel_right_trigger = 50

# Общие
test_on_start = true
verbose_log = true
```

## Обновление игры

Мод использует Steam Launch Options вместо замены файлов игры. Обновления игры не должны его ломать.

Если вибрация пропала после обновления, перезапустите `./scripts/install.sh` или нажмите «Установить» в GUI-приложении.

## Удаление

**GUI:** Нажмите «Удалить» в VibFix.app.

**Командная строка:**
```bash
./scripts/uninstall.sh
```

Удаляет Steam Launch Options. Конфиг и dylib не удаляются.

## Сборка из исходников

```bash
# Установить Xcode Command Line Tools (если ещё не установлены)
xcode-select --install

# Собрать всё (dylib, лаунчер, GUI-приложение)
make all

# Или собрать и скопировать в build/
chmod +x build.sh
./build.sh
```

## Как это работает

1. Установщик прописывает Steam Launch Options для использования обёртки-лаунчера
2. Обёртка устанавливает `DYLD_INSERT_LIBRARIES` для инъекции фикса в процесс игры
3. Фикс хукает IL2CPP-рантайм Unity:
   - Заставляет `SystemInfo.supportsVibration` возвращать `true`
   - Перехватывает `NativeInputSystem.IOCTL` для захвата команд вибрации
4. Вывод вибрации (два пути):
   - **Steam Input API** — основной метод, использует подсистему контроллеров Steam
   - **IOKit HID** — автоматический фоллбек, отправляет Xbox Bluetooth HID-репорты напрямую

Оба пути проверяются при запуске. Steam Input используется если доступен; HID-фоллбек активируется мгновенно если Steam Input недоступен.

## Решение проблем

| Проблема | Решение |
|----------|---------|
| Нет тестовой вибрации при запуске | Проверьте `vibfix.log`. Убедитесь, что Steam Input включён. |
| Контроллер не определяется | Переподключите контроллер, перезапустите игру. Проверьте что Steam видит контроллер. |
| Игра падает при запуске | Запустите `./scripts/uninstall.sh`, затем `./scripts/install.sh`. |
| Вибрация ощущается неправильно | Отредактируйте `config.txt` — поменяйте проценты моторов. |
| Вибрация при вываживании слабая | Исправлено в v9.0. Обновитесь до последней версии. |

## Changelog

### v9.0
- **GUI-приложение** (`VibFix.app`): нативный macOS установщик/конфигуратор с тёмной темой Fishing Planet, баннером, иконкой геймпада, слайдерами, переключением языка RU/EN
- **Steam Launch Options**: установщик автоматически настраивает Launch Options (больше не нужна замена бинарников и ежедневный переустанов)
- **Новый лаунчер** (`launch_wrapper.c`): корректно обрабатывает `.app`-пути, сохраняет Steam overlay в `DYLD_INSERT_LIBRARIES`
- **Исправлена вибрация вываживания**: нормализация lowFreq с [0, 0.30] в [0, 1.0] — раньше вибрация была почти неощутима (4-13% вместо 45-100%)
- **Подробный лог**: новая опция `verbose_log` — логирует каждый запрос вибрации для отладки
- **Детекция HIGH-событий**: обнаружение событий только с highFreq (для анализа игры)

### v8.0
- **IOKit HID фоллбек**: если Steam Input недоступен, вибрация работает через прямые Xbox Bluetooth HID-репорты (тот же подход что в [GRID Autosport vibfix](https://github.com/LynxEsq/grid-autosport-vibfix))
- **Исправлена инициализация Steam Input**: добавлена проверка `SteamAPI_GetHSteamPipe/User` перед вызовом `SteamInput()` — это было причиной ошибки «SteamInput() returned NULL» в v7.0
- **Увеличено количество ретраев Steam Input**: 60 попыток (30 секунд) вместо 10 (5 секунд)
- **Диагностика IOCTL**: логируются все типы Unity IOCTL-вызовов (первые 10 + периодически), не только RMBL
- **Унифицированный вывод вибрации**: абстракция `outputRumble()` направляет вибрацию в доступный бекенд (Steam Input или HID)

### v7.0
- Первый публичный релиз
- IL2CPP хуки для `SupportsVibration` и `IOCTL`
- Steam Input API для вывода вибрации
- Настраиваемая сила моторов для поклёвки/вываживания
- Эффект двойного удара при поклёвке
