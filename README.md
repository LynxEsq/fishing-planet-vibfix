# Fishing Planet — Xbox Controller Vibration Fix (macOS)

Enables Xbox controller vibration in Fishing Planet on macOS. The game has built-in vibration support but Unity disables it on macOS. This mod hooks into Unity's runtime and redirects vibration commands through Steam's Input API.

**[Русская версия ниже / Russian version below](#ru)**

---

## Requirements

- macOS 13+ (Apple Silicon)
- Fishing Planet via Steam
- Xbox controller connected via Bluetooth
- Xcode Command Line Tools (`xcode-select --install`)

## Installation

```bash
git clone https://github.com/LynxEsq/fishing-planet-vibfix.git
cd fishing-planet-vibfix

chmod +x install.sh uninstall.sh
./install.sh
```

### Enable Steam Input (required)

The fix uses Steam's API to vibrate the controller. Without this, vibration won't work.

1. Open Steam
2. Right-click **Fishing Planet** > **Properties**
3. Go to **Controller** tab
4. Set to **Enable Steam Input**

### macOS Input Monitoring permission (important)

On first launch, macOS will ask to grant **Input Monitoring** (or **Accessibility**) permission to the game. This is needed for the controller to work properly.

**If the game had this permission before installation**, you must reset it:

1. Go to **System Settings** > **Privacy & Security** > **Input Monitoring**
2. Find **FishingPlanet** and **remove it** (click "−")
3. Launch the game — macOS will ask for permission again
4. **Allow** it

This is necessary because the installer replaces the game's launch binary, and macOS ties permissions to the specific binary file.

### Verify it works

1. Launch Fishing Planet through Steam
2. **Short test vibration on start** = everything is working correctly
3. Go fishing — you'll feel vibration on bite and during reeling

If there's no test vibration, check `vibfix.log` in the mod directory.

## Configuration

Edit `config.txt` to customize vibration strength. Changes apply on next game restart.

```ini
# Values are 0-100 (percentage of motor strength)
#
# Controller motors:
#   left_motor    = low-frequency heavy rumble ("thump")
#   right_motor   = high-frequency light buzz ("whirr")
#   left_trigger  = left trigger motor (Xbox Elite / DualSense)
#   right_trigger = right trigger motor (Xbox Elite / DualSense)

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

# Test vibration on game start (confirms the fix is working)
test_on_start = true
```

## Game updates

When Fishing Planet updates via Steam, it may replace the launcher binary. If vibration stops working after an update:

```bash
./install.sh
```

The installer backs up the new binary and re-installs the launcher wrapper.

**After re-installing**, reset the Input Monitoring permission (see above) — macOS needs to re-authorize the new binary.

## Uninstall

```bash
./uninstall.sh
```

Restores the original game binary. Config and dylib are not deleted.

## How it works

1. A launcher wrapper sets `DYLD_INSERT_LIBRARIES` to inject the fix into the game process
2. The fix hooks Unity's IL2CPP runtime:
   - Forces `SystemInfo.supportsVibration` to return `true`
   - Intercepts `NativeInputSystem.IOCTL` to capture vibration commands
3. Vibration commands are sent to the controller via Steam Input API

CoreHaptics doesn't work while Unity holds the HID device, so Steam Input is the only viable approach on macOS.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| No test vibration on start | Check `vibfix.log`. Make sure Steam Input is enabled. Reset Input Monitoring permission. |
| Controller not detected | Reconnect controller, restart game. Check Steam sees it. |
| Game crashes on start | Run `./uninstall.sh`, then `./install.sh`. Reset Input Monitoring permission. |
| Vibration feels wrong | Edit `config.txt` — adjust motor percentages. |
| Permission popup doesn't appear | Manually add FishingPlanet in System Settings > Privacy > Input Monitoring. |

## Files

| File | Description |
|------|-------------|
| `vibration_fix.m` | Main dylib — IL2CPP hooks + Steam Input API |
| `launcher.c` | Wrapper binary that injects the dylib |
| `config.txt` | Vibration settings (user-editable) |
| `install.sh` | Build & install script |
| `uninstall.sh` | Restore original game binary |
| `Makefile` | Build rules |

## License

MIT

---

<a name="ru"></a>
# Fishing Planet — Фикс вибрации Xbox-контроллера (macOS)

Включает вибрацию Xbox-контроллера в Fishing Planet на macOS. В игре есть встроенная поддержка вибрации, но Unity отключает её на macOS. Этот мод перехватывает команды вибрации и перенаправляет их через Steam Input API.

## Требования

- macOS 13+ (Apple Silicon)
- Fishing Planet через Steam
- Xbox-контроллер по Bluetooth
- Xcode Command Line Tools (`xcode-select --install`)

## Установка

```bash
git clone https://github.com/LynxEsq/fishing-planet-vibfix.git
cd fishing-planet-vibfix

chmod +x install.sh uninstall.sh
./install.sh
```

### Включить Steam Input (обязательно)

Фикс использует API Steam для управления вибрацией. Без этого вибрация не будет работать.

1. Откройте Steam
2. ПКМ на **Fishing Planet** > **Свойства**
3. Вкладка **Контроллер**
4. Выберите **Включить Steam Input**

### Разрешение «Мониторинг ввода» в macOS (важно)

При первом запуске macOS попросит дать разрешение **Мониторинг ввода** (Input Monitoring) для игры. Это нужно для работы контроллера.

**Если игра уже имела это разрешение до установки**, его нужно сбросить:

1. Откройте **Системные настройки** > **Конфиденциальность и безопасность** > **Мониторинг ввода**
2. Найдите **FishingPlanet** и **удалите** его (нажмите "−")
3. Запустите игру — macOS снова попросит разрешение
4. **Разрешите**

Это необходимо потому, что установщик заменяет бинарный файл запуска игры, а macOS привязывает разрешения к конкретному файлу.

### Проверка работы

1. Запустите Fishing Planet через Steam
2. **Короткая тестовая вибрация при запуске** = всё работает правильно
3. Идите на рыбалку — вибрация при поклёвке и вываживании

Если тестовой вибрации нет — проверьте `vibfix.log` в директории мода.

## Настройка

Редактируйте `config.txt` для настройки силы вибрации. Изменения применяются при следующем запуске игры.

```ini
# Значения 0-100 (процент силы мотора)
#
# Моторы контроллера:
#   left_motor    = низкочастотный тяжёлый мотор ("удар")
#   right_motor   = высокочастотный лёгкий мотор ("жужжание")
#   left_trigger  = мотор левого триггера (Xbox Elite / DualSense)
#   right_trigger = мотор правого триггера (Xbox Elite / DualSense)

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

# Тестовая вибрация при запуске (подтверждение работы)
test_on_start = true
```

## Обновление игры

Если после обновления игры через Steam вибрация пропала:

```bash
./install.sh
```

Установщик сохранит новый бинарник и переустановит обёртку.

**После переустановки** сбросьте разрешение «Мониторинг ввода» (см. выше) — macOS должен заново авторизовать новый файл.

## Удаление

```bash
./uninstall.sh
```

Восстанавливает оригинальный бинарник игры. Конфиг и dylib не удаляются.

## Как это работает

1. Обёртка-лаунчер устанавливает `DYLD_INSERT_LIBRARIES` для инъекции фикса в процесс игры
2. Фикс хукает IL2CPP-рантайм Unity:
   - Заставляет `SystemInfo.supportsVibration` возвращать `true`
   - Перехватывает `NativeInputSystem.IOCTL` для захвата команд вибрации
3. Команды вибрации отправляются на контроллер через Steam Input API

CoreHaptics не работает пока Unity держит HID-устройство, поэтому Steam Input — единственный рабочий подход на macOS.

## Решение проблем

| Проблема | Решение |
|----------|---------|
| Нет тестовой вибрации при запуске | Проверьте `vibfix.log`. Убедитесь, что Steam Input включён. Сбросьте разрешение «Мониторинг ввода». |
| Контроллер не определяется | Переподключите контроллер, перезапустите игру. Проверьте что Steam видит контроллер. |
| Игра падает при запуске | Запустите `./uninstall.sh`, затем `./install.sh`. Сбросьте разрешение «Мониторинг ввода». |
| Вибрация ощущается неправильно | Отредактируйте `config.txt` — поменяйте проценты моторов. |
| Не появляется запрос разрешения | Вручную добавьте FishingPlanet в Системные настройки > Конфиденциальность > Мониторинг ввода. |
