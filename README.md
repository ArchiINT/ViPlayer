# ViPlayer

Музыкальный плеер для **Linux** и **Android**: своя медиатека из папок на
устройстве, скачивание треков **по ссылке** и **по названию** (YouTube Music,
SoundCloud, Spotify-ссылки) и **полная синхронизация** ПК ↔ телефон по локальной
сети — без серверов и аккаунтов. Чёрный интерфейс с неоновыми акцентами.

> Статус: **этап 1 — каркас** (структура, тема, БД, локализация, скрипты).
> План и принятые решения — [docs/ROADMAP.md](docs/ROADMAP.md).

## Документация

| Файл | О чём |
|---|---|
| [docs/ROADMAP.md](docs/ROADMAP.md) | решения по продукту, этапы, планы на будущее |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | структура кода, слои, БД, соглашения |
| [docs/RELEASE.md](docs/RELEASE.md) | сборка, установка и **обновление без потери данных** |
| [docs/SYNC.md](docs/SYNC.md) | как устроена синхронизация |
| [docs/DOWNLOADS.md](docs/DOWNLOADS.md) | источники скачивания и форматы |

## Требования

- **Flutter** (stable) в `~/flutter` — или укажите `FLUTTER=/путь/к/flutter/bin/flutter`.
- **Системные пакеты (Arch):**
  ```bash
  sudo pacman -S --needed clang cmake ninja pkgconf gtk3 jdk17-openjdk mpv yt-dlp ffmpeg android-tools zip
  ```
  `mpv` — движок воспроизведения (libmpv), `yt-dlp` + `ffmpeg` — скачивание на ПК,
  `android-tools` — `adb` для установки на телефон.
- **Android SDK** (командные инструменты или Android Studio).

Проверка окружения: `~/flutter/bin/flutter doctor`.

## Быстрый старт (разработка)

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # код Drift
flutter run -d linux                                         # или -d <телефон>
```

## Основные команды

| Команда | Что делает |
|---|---|
| `scripts/deploy-all.sh` | проверки → обновить ПК и телефон (`--linux` / `--phone`) |
| `scripts/install-linux-desktop.sh` | собрать и установить в меню приложений + команда `viplayer` |
| `scripts/build-apk.sh` | собрать подписанный APK |
| `scripts/create-keystore.sh` | **один раз**: создать постоянный ключ подписи |
| `scripts/bump-version.sh [patch\|minor\|major]` | поднять версию |
| `scripts/db-schema.sh` | после изменения таблиц: снапшот схемы + тесты миграций |
| `flutter analyze && flutter test` | проверки |

Подробно об обновлении телефона без потери данных — [docs/RELEASE.md](docs/RELEASE.md).

## Лицензии сторонних ресурсов

Шрифты Inter, JetBrains Mono и Orbitron — SIL Open Font License
(`assets/fonts/OFL-*.txt`).
