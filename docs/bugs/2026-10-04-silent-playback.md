# Тишина при «играющем» треке (Android 16)

**Дата:** 2026-10-04 · **Версия с исправлением:** 1.2.2 · **Устройство:** Android 16

## Проблема

Иногда на телефоне пропадал звук: трек показан играющим, ползунок идёт, а звука
нет — и в наушниках, и через динамик. Помогало только «пауза → плей».

## Как искали

Android хранит историю звука до перезагрузки: `adb shell dumpsys audio`.

1. **Журнал фокуса** (`focus commands as seen by MediaFocusControl`):

   ```
   12:00:00 requestAudioFocus() ... callingPack=com.example.other req=2         ← другое приложение, временно
   12:00:00 focus owner: ... com.viplayer.app code: -2 event: handleLoss          ← у нас забрали
   12:02:10 focus owner: ... com.viplayer.app code: 1 event: handleGain           ← вернули
   ```

   ViPlayer корректно встал на паузу и после возврата фокуса продолжил играть.

2. **Защита Android 16** — рядом нашлась строка, которая всё объяснила:

   ```
   12:04:00:082 AudioHardening background playback would be muted for com.viplayer.app
   12:04:00:083 player piid:12345 event:muted updated source:portVolume
   ```

   В ту же миллисекунду система заглушила плеер ViPlayer.

## Причина

- `audio_service` по умолчанию (`androidStopForegroundOnPause: true`) на
  **паузе выводит приложение из foreground-режима** — убирает статус
  «проигрывает медиа».
- Android 16 (**AudioHardening**) глушит воспроизведение, которое начинает
  **фоновое** приложение без такого статуса.
- Продолжение после звонка / видео в другом приложении / уведомления как раз происходит из фона:
  пауза сняла статус → плеер стартует «фоновым» → звук заглушён. Плеер (mpv) об
  этом не знает и честно «играет». Пауза и плей в самом приложении запускают
  воспроизведение «на виду», поэтому звук возвращался.

## Решение

1. **На паузе остаёмся в foreground** — `androidStopForegroundOnPause: false`
   (`lib/core/player/audio_handler.dart`). Продолжение из фона больше не глушится.
2. **Через 10 минут паузы отпускаем foreground** — иначе телефон держал бы
   блокировку сна (wake lock) бесконечно. Dart по таймеру вызывает
   `PlaybackServiceChannel.kt` → штатный `exitForegroundState()` у
   `audio_service`: статус и wake lock сняты, уведомление остаётся (теперь его
   можно смахнуть). Следующий «плей» снова входит в foreground.
   - Метод в `audio_service` 0.18 приватный — вызывается через reflection,
     защищён от R8 правилом в `android/app/proguard-rules.pro`. Если в новой
     версии плагина метод пропадёт, вызов просто не сработает (в лог), а
     приложение останется в foreground на паузе — звук это не ломает.

## Проверка (на телефоне, через adb)

| Сценарий | foreground | Звук (`mutedState`) |
|---|---|---|
| Играет | да | none |
| Короткая пауза в фоне | **да** (раньше — нет) | — |
| Продолжение из фона | да | **none** (раньше — muted) |
| Пауза дольше таймаута | нет, уведомление осталось | — |
| Плей с наушников после долгой паузы | да | none |

Новых записей `AudioHardening ... would be muted` для ViPlayer после
исправления нет.

```sh
adb shell dumpsys audio | grep -E "AudioHardening.*viplayer"
adb shell dumpsys activity services com.viplayer.app | grep isForeground
```

## Если повторится

Сразу, без перезагрузки телефона: `adb shell dumpsys audio > audio.txt` и
искать `com.viplayer.app` в разделах фокуса, `AudioHardening` и событиях
плееров (`muted updated source:`).
