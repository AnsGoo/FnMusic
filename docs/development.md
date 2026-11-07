# Development and verification

This guide keeps the build, architecture, protocol, and asset details out of the reader-facing READMEs. For behavior and settings, see [Features](features.md).

## Build from source

Requirements:

- Android SDK 37.
- JDK 21. Gradle provisions its daemon toolchain from [`gradle/gradle-daemon-jvm.properties`](../gradle/gradle-daemon-jvm.properties); the Android compile target is Java 17.
- Git submodules, including the pinned lyrics dependencies.

```sh
git clone --recurse-submodules https://github.com/seasonyuu/FnMusic.git
cd FnMusic
./gradlew :app:assembleDebug
```

For an existing checkout, run `git submodule update --init --recursive` before building. Install `app/build/outputs/apk/debug/app-debug.apk` with an in-place update if the app is already installed. Do not clear an existing app's data to fix an installation error. See [third-party dependencies](../third_party/README.md) for pinned sources and adapters.

If a user-level Gradle proxy is unavailable, disable it for this invocation:

```sh
./gradlew :app:assembleDebug -Dhttp.proxyHost= -Dhttps.proxyHost=
```

## Modules

FnMusic uses a Jetpack Compose main activity. Folder authorization runs in a separate,
non-exported native Activity with a View-based toolbar and WebView; a typed Activity
Result contract carries the request and result without embedding the WebView in
Compose navigation or backdrop layers. The main boundaries are:

| Module | Responsibility |
| --- | --- |
| `:app` | Entry point, navigation shell, and dependency wiring (`AppGraph` / `AppModule`) |
| `:core:model` | Domain models |
| `:core:network` | fnOS Music API client, FN Connect discovery, relay activation, `authx` signing, session maintenance, and the Music Free source adapter |
| `:core:player` | Media3 playback service and media session |
| `:core:designsystem` | Themes, liquid-glass components, and responsive navigation |
| `:data` | Repositories, Room / DataStore, LRC parsing, and optimistic favorites |
| `:feature:session` | Connection and sign-in UI |
| `:feature:music` | Library, player, settings, and administration UI |

The project uses Kotlin, Compose Material 3 and adaptive layouts, Media3 / ExoPlayer, Hilt, Room, DataStore, Paging 3, OkHttp / Retrofit, kotlinx.serialization, Coil 3, and [Backdrop](https://github.com/Kyant0/AndroidLiquidGlass). Versions are pinned in the Gradle catalogs rather than this document.

## Library sources

The connection screen only offers a Music Free server; FN Connect and direct fnOS
addresses are no longer selectable, though `Endpoint.FnConnect` / `Endpoint.Direct`
remain so previously saved sessions still restore. Repositories hold
`MusicApiRouter`, a stable handle whose delegate is switched by
`SessionCoordinator` when a session is established. The fnOS Retrofit client
remains the default, so the original path is unchanged and no repository, screen
or player code needs to know which backend is active.

Branding follows the Music Free source: the launcher icon, the login logo and the
sidebar logo all use its vinyl artwork. The adaptive icon draws the artwork as a
density-bucketed foreground (`drawable-*/ic_launcher_foreground.png`) on the
record's shell colour, and `ic_launcher_monochrome.xml` keeps a vinyl silhouette
for themed icons.

The adapter lives in `core/network/.../musicfree/` and covers the song library,
albums, artists, playlists, favorites and play history, plus the search endpoints
those screens use. It mixes OpenSubsonic `/rest/*.view` endpoints (starred,
star/unstar, album / artist / playlist contents) with Music Free's own
`/rest/api/v1/*` endpoints (paged songs, albums and artists; playlists; play
history). Every request sends `f=json`; the client accepts both the
`subsonic-response` envelope and bare JSON. Endpoints without server-side paging
are paged in memory on the 1-based page numbers used by `ApiPagingSource`.

`MusicFreeUrls` builds absolute media URLs carrying Subsonic `u/t/s` credentials,
because Media3 and Coil cannot attach headers to a URL string. The existing
`DynamicBaseUrlInterceptor` passes absolute URLs through untouched, so the
playback and image-loading clients need no changes. fnOS-only capabilities
(administration, transcoding, folder authorization, metadata editing and
playlist cover upload) return empty results on this source; online lyrics still
work through the existing providers. `GET /rest/stream` already records a play,
so `reportEvent` is deliberately a no-op to avoid double counting.

Roaming has no Music Free equivalent, so `roam-start` and `roam-next` synthesize
a window from `GET /rest/getRandomSongs.view`. `RoamQueue` consumes only
`current` and `next`, and every item gets a unique `roamId` — a repeated track
must still look new, otherwise the prefetch in `extendRoamFrom` short-circuits
and the queue stops growing. Recently served tracks are filtered out through a
32-entry memory, which falls back to the raw response once a library is smaller
than that.

`Media3PlayerController` steps over sources it cannot read instead of parking the
queue on an error, because a random roam window makes one dead file fatal for the
whole session. Missing files, rejected responses, unparseable containers and
undecodable formats are all treated as skippable; connection loss is not, since a
dropped network says nothing about the next track. Twenty consecutive skips means
the queue itself is broken, so the error surfaces instead of scrolling forever.

Music Free uses a JWT for API calls and serves plain HTTP on the LAN by default,
so an `http://` address requires the "allow private LAN HTTP" option. The JWT and
derived Subsonic credentials are kept in the existing encrypted vault. The plain
password is never persisted for this source, so an expired token requires the
user to sign in again.

Artist counts come from the Navidrome-compatible `GET /api/artist`, the only
listing that reports a per-artist song count; `/rest/api/v1/artists` exposes just
`albumCount`. That count is only correct once the server credits multi-artist
songs: Music Free stores the first artist of `"A / B / C"` in `songs.artist_id`
and the full list in `song_artists`, so a server that counts only the former
reports zero for every featured artist. `CountVisibleSongsByArtist` and the
`artist_id` filter of `GET /api/song` therefore union both sources. On an older
server the list falls back to naming the album count instead of claiming zero
songs, and the detail header and track list fall back to the albums'
`songCount` and contents. `GET /api/artist` and `GET /api/song` cap `_limit` at
100 per request, so the adapter stitches larger Paging loads together.

`GET /api/song` omits `coverArt` (it only sets `hasCoverArt`); `getCoverArt`
accepts an album id, so the album id is used as the cover handle.

Playlists are managed through Music Free's own `/rest/api/v1/playlists` CRUD,
which accepts one song per add/remove request. Playlist covers need the playlist
to exist first (`PUT /rest/api/v1/playlists/:id/cover` takes a multipart upload),
so creating a playlist here skips the fnOS-only pre-create cover upload instead
of failing.

`/rest/api/v1/play-history` returns one row per play with `artist` and `album`
as embedded objects (the library list uses plain strings). The adapter reads both
shapes and collapses repeats to one entry per song, keeping the most recent play,
because the list renders with the track id as its `LazyColumn` key.

## Protocol and verification

[`api.md`](../api.md) records the observed fnOS Music web protocol: FN Connect discovery, relay handshake, `authx` signing, and music endpoints. It contains no account credentials, cookies, or tokens. These behaviors are not an official public fnOS API.

| Tool | Purpose |
| --- | --- |
| [`verify_fn_connect.py`](../scripts/verify_fn_connect.py) | Full FN Connect flow: entry, discovery, relay, sign-in, and read-only probes |
| [`verify_api.py`](../scripts/verify_api.py) | Music-service read/write probes with a redacted JSON report |
| [`test_verify_fn_connect.py`](../scripts/test_verify_fn_connect.py) | Offline verifier unit tests |

Real-NAS write verification reads credentials only from an untracked `.env` based on [`.env.example`](../.env.example). Verification reports (`*-verification-report.json`) must not be committed. Read/write probes and playback against a live NAS are separate from local fixture tests.

Choose tests by changed behavior using [the testing guide](testing.md). The local starting points are:

```sh
./gradlew testDebugUnitTest
python3 -m unittest discover -s scripts -p 'test_verify_*.py' -v
```

Device tests require a dedicated test emulator because runner cleanup may remove apps or data. See [the preservation rules](../AGENTS.md#emulator-app-and-data-preservation) before running them.

## Security and privacy

Remembered login fields, login digest, tokens, and connection configuration are encrypted using Keystore-wrapped AES-GCM keys. The password digest can still be used for replay login, so logs must never include digests, cookies, tokens, request bodies, or media identifiers.

HTTPS uses system certificate authorities and has no certificate-bypass option. Plain HTTP is accepted only for loopback, RFC 1918, link-local, or IPv6 ULA addresses; redirect targets are checked again by the network interceptor.

Online lyric searches send song titles and artist names to the selected provider. NAS credentials are not sent to lyric providers. See [Features](features.md#lyrics) for source selection and caching behavior.

## Assets and trademarks

The [README icon](assets/fnmusic-icon.svg) is a vector adaptation of the original logo, with a fixed rounded-square mask to match the Android adaptive icon. The logo, Montserrat font, home decoration images, and some navigation SVGs come from the user's fnOS Music web build and are used for personal sideloading only. Sources, build hashes, and file digests are in [`web-assets/manifest.json`](web-assets/manifest.json).

The [README screenshots](assets/screenshots/) were captured from a development emulator. They contain music-library artwork returned by a NAS; the APK does not bundle those covers. Artwork and trademarks remain the property of their respective owners. Before distributing the app publicly, re-check the licensing of fnOS branding, logo, fonts, icons, and decoration assets.

FnMusic-authored code and original documentation are licensed under [Apache License 2.0](../LICENSE), with the covered material and exceptions explained in the [license scope](../LICENSE-SCOPE.md). Third-party components retain their own licenses. The project is not affiliated with or endorsed by fnOS.
