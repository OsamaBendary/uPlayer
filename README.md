# uPlayer

A high-performance, aesthetically crafted local music player built with Flutter. Designed for smooth, responsive user experiences, dynamic thematic backgrounds, and seamless audio playback — with a powerful Go-based download engine that can fetch lossless FLAC straight from your streaming providers.

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Go](https://img.shields.io/badge/Go-00ADD8?style=for-the-badge&logo=go&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)

---
## Download APK
<p align="center">
  <a href="https://github.com/OsamaBendary/uPlayer/releases/latest">
    <img src="https://img.shields.io/badge/Download-Latest%20APK-0078D4?style=for-the-badge&logo=android&logoColor=white" height="64"/>
  </a>
</p>

## App Showcase
<img width="1920" height="1440" alt="596shots_so" src="https://github.com/user-attachments/assets/4bb33f95-5c39-4d0e-80ac-aa9769436301" />

<img width="1920" height="1440" alt="765shots_so" src="https://github.com/user-attachments/assets/e840149e-644b-497f-80a0-56fb97bb3b32" />

<img width="1920" height="1440" alt="141shots_so" src="https://github.com/user-attachments/assets/51b1f855-c8d7-434b-85c4-4a93ee7d6886" />

## Key Features

* **Go-Powered Lossless Downloads**: A native Go (gomobile) backend handles downloading in the background. Pick FLAC 16/44 or FLAC 24-bit and the engine automatically prioritizes lossless-capable providers (Tidal, Qobuz, Deezer, Amazon, Apple Music, Pandora) over lossy ones — no more surprise Opus files.
* **Extension Store & Streaming Providers**: Install streaming-provider extensions (Tidal, Qobuz, Deezer, SoundCloud, YouTube Music, ...) directly from the in-app store and manage them from Settings.
* **Zero-Login Verification**: Provider verification happens through a browser-based challenge that deep-links straight back into the app (`spotiflac://`/`uplayer://`), so you can authorize Tidal/Qobuz without ever typing credentials into the app.
* **Download Destination Control**: Choose exactly where downloaded music lands — the public `Music/uPlayer` folder (with "All files access" granted on Android 10+) or any folder you pick.
* **Dynamic Aesthetic UI**: Custom extracted color palettes render adaptive gradient backgrounds matching active track artwork.
* **Customization Screen**: Tune the player to your taste — choose what happens when you tap a song (open the player, or just play in the mini player), pick the seek bar style, and switch artwork styles.
* **Five Artwork Styles**: Classic square album art, a spinning Picture Disc, a Classic Silver CD, a Jewel Case, or a Minimal Dark CD — all switchable from Settings → Customization.
* **Buttery-Smooth Waveform Seekbar**: Real-time waveform visualizer with sub-millisecond 1:1 touch calibration, scrubbing, and a ticker-driven interpolation that glides smoothly instead of jumping column-by-column.
* **Glassy Floating Navigation Bar**: Persistent, floating bottom navigation bar featuring a glassmorphism blur backdrop, quick tab switching, and seamless screen transitions.
* **Mini Player**: A compact always-available now-playing card above the navigation bar with playback controls — and every message/snackbar in the app pops up *above* it, never behind it.
* **Playlist Management**: Create, rename, delete, and manage custom playlists. Includes a custom cover image picker from device gallery and a searchable song picker interface.
* **Pinned Liked Songs**: Dedicated Liked Songs card pinned at the top of the playlists tab for instant access to favorited tracks.
* **Listening Statistics**: Dedicated Stats screen showcasing top songs, artists, and albums ranked by play count and listening duration. Play counts register accurately at 50% song playback threshold.
* **Settings & Folder Filtering**: Customize audio scanning directories with folder filtering, clear play statistics, and app information.
* **Multi-Album Artwork Precision**: Automatic distinction between single-album views and mixed-album lists, rendering distinct per-song artwork when viewing multi-album tracks.
* **Ultra-Smooth Performance**: Native canvas rendering via isolated stream controllers ensures playback position updates operate without whole-tree UI rebuilds.
* **Full-Screen Lyrics View**: Immersive full-screen lyrics screen featuring fluid transition animations anchored directly to player controls.
* **Queue & Playback Control**: Rich queue management supporting shuffle modes, repeat options (track/queue/play-once), and custom sleep timers.
* **Artist Hero Transitions**: Custom shuttle builders maintain smooth circular geometry during hero transitions between artist cards and headers.

---

## Built With

* **[Flutter](https://flutter.dev/)** — UI Framework
* **[Go](https://go.dev/) + [gomobile](https://pkg.go.dev/golang.org/x/mobile)** — Native download backend (streaming, extraction, tagging, FLAC encoding)
* **[just_audio](https://pub.dev/packages/just_audio)** — High-performance audio engine
* **[on_audio_query](https://pub.dev/packages/on_audio_query)** — Local device audio library scanner
* **[image_picker](https://pub.dev/packages/image_picker)** — Custom playlist artwork image picker
* **[shared_preferences](https://pub.dev/packages/shared_preferences)** — Local persistence for playlists, favorites, play counts, and preferences
* **[http](https://pub.dev/packages/http)** — Synchronized lyrics fetching via open APIs

---

## Credits

* Huge thanks to **[SpotiFLAC](https://github.com/spotbye/spotiflac)** and **[SpotiFLAC Mobile](https://github.com/spotiflacapp/SpotiFLAC-Mobile)** — the reference implementations that the download engine, provider-extension system, and zero-login session verification are modeled after. uPlayer builds on their architecture for streaming-provider downloads.
* Icons via [SVG Repo](https://www.svgrepo.com/).

---

## License

This project is for portfolio and educational purposes.
