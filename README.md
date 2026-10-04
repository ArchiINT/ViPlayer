# ViPlayer

Музыкальный плеер для **Linux** и **Android**: своя медиатека из папок на
устройстве, скачивание треков **по ссылке** и **по названию** (YouTube Music,
SoundCloud, Spotify-ссылки) и **полная синхронизация** ПК ↔ телефон по локальной
сети — без серверов и аккаунтов. Интерфейс в стиле «стекло» поверх размытых обложек.

> Версия **1.0.0** — см. [CHANGELOG.md](CHANGELOG.md).

## Как пользоваться

| Что | Где |
|---|---|
| Добавить музыку | Настройки → Папки с музыкой (на телефоне музыка устройства подхватывается сама) |
| Слушать | нажать трек; меню трека — долгое нажатие / правый клик (в очередь, лайк, в плейлист…) |
| Плеер | мини-плеер внизу → нажать или смахнуть вверх |
| Клавиши (ПК) | пробел — пауза, ←/→ — перемотка 5 с, Ctrl+←/→ — трек назад/вперёд |
| Скачать по ссылке | Загрузки → По ссылке → вставить → Скачать |
| Скачать по названию | Загрузки → По названию → ▶ прослушать → отметить → Скачать выбранные |
| Синхронизация | Настройки → Синхронизация → Связать (код с другого устройства) |
| Формат загрузок, yt-dlp | Настройки → Загрузки |
| Журнал ошибок | Настройки → О приложении |

## Документация

| Файл | О чём |
|---|---|
| [docs/ROADMAP.md](docs/ROADMAP.md) | решения по продукту, этапы, планы на будущее |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | структура кода, слои, БД, соглашения |
| [docs/RELEASE.md](docs/RELEASE.md) | сборка, установка и **обновление без потери данных** |
| [docs/SYNC.md](docs/SYNC.md) | как устроена синхронизация |
| [docs/DOWNLOADS.md](docs/DOWNLOADS.md) | источники скачивания и форматы |
| [CHANGELOG.md](CHANGELOG.md) | что изменилось в версиях |

## Требования

- **Flutter** (stable) в `~/flutter` — или укажите `FLUTTER=/путь/к/flutter/bin/flutter`.
- **Системные пакеты (Arch):**
  ```bash
  sudo pacman -S --needed clang cmake ninja pkgconf gtk3 jdk17-openjdk mpv yt-dlp deno ffmpeg android-tools zip
  ```
  `mpv` — движок воспроизведения (libmpv), `yt-dlp` + `deno` + `ffmpeg` — скачивание на ПК (deno нужен yt-dlp для YouTube),
  `android-tools` — `adb` для установки на телефон.
- **Android SDK** (командные инструменты или Android Studio).

Проверка окружения: `~/flutter/bin/flutter doctor`.

Для синхронизации с телефоном откройте в брандмауэре ПК порты ViPlayer
(UDP 48125, TCP 48126) — см. [docs/SYNC.md](docs/SYNC.md#брандмауэр-на-пк).

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
| `scripts/generate-icons.sh` | после правки `assets/icon/*.svg`: иконки Android и Linux |
| `flutter analyze && flutter test` | проверки |
| `scripts/perf-test.sh <папка>` | замер плавности (время кадров) |
| `scripts/playback-test.sh <папка>` | проверка воспроизведения через настоящий движок (без звука) |
| `flutter test --tags online --run-skipped` | проверка источников скачивания на реальных сервисах |

Подробно об обновлении телефона без потери данных — [docs/RELEASE.md](docs/RELEASE.md).

## Лицензии сторонних ресурсов

Шрифты Inter, JetBrains Mono и Orbitron — SIL Open Font License
(`assets/fonts/OFL-*.txt`).
