# MusicFly (Flutter)

MusicFly（中文名：乐记）— a Music Free client for macOS, Windows, Android and
iOS. It talks to a Music Free server (Navidrome / Subsonic compatible):
`/rest/api/v1/*` for the REST surface and `/rest/stream` for audio.

The Dart package is `musicfly`; platform identifiers are
`com.seasonyuu.musicfly`. On screen the app is called 乐记.

## Layout

| Path | Contents |
| --- | --- |
| `lib/data` | Models, the Music Free HTTP client, session persistence |
| `lib/audio` | `just_audio` wrapper; owns no queue logic |
| `lib/state` | `AppModel` — navigation, listings, queue, lyrics |
| `lib/ui` | Theme, controls, screens |

## Run

```sh
flutter run -d macos        # or windows
flutter test                # unit tests
```

`test/live_backend_test.dart` only runs against a real server:

```sh
MUSICFLY_TEST_SERVER=http://192.168.1.10:4533 \
MUSICFLY_TEST_USER=admin MUSICFLY_TEST_PASSWORD=admin \
flutter test test/live_backend_test.dart
```

## Package for macOS

```sh
./scripts/package_macos.sh        # from the repository root
```

Produces `dist/MusicFly-<version>-macos.dmg`. The bundle is signed ad-hoc, so a
downloaded copy needs right-click → Open on first launch.
