#  u_player

A high-performance, aesthetically crafted local music player built with Flutter. Designed for smooth, responsive user experiences, dynamic thematic backgrounds, and seamless audio playback.

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)

---

##  Key Features

*  **Dynamic Aesthetic UI**: Uses custom extracted color palettes to render adaptive gradient backgrounds matching the active track artwork.
*  **Ultra-Smooth Performance**: Native canvas rendering via `RepaintBoundary` and isolated stream controllers ensure playback position updates operate without triggering whole-tree UI rebuilds.
*  **Interactive Waveform Seekbar**: Real-time waveform visualizer with sub-millisecond 1:1 touch calibration and scrubbing.
*  **Full-Screen Lyrics View**: Immersive, full-screen lyrics screen featuring fluid transition animations anchored directly to the player controls.
*  **Queue & Playback Control**: Rich queue management supporting shuffle modes, repeat options (list/track), and custom sleep timers.
*  **Adaptive Layouts**: Responsive scaling across screen sizes with dynamic marquee scrolling for oversized song metadata.

---

##  Built With

* **[Flutter](https://flutter.dev/)** — UI Framework
* **[just_audio](https://pub.dev/packages/just_audio)** — High-performance audio engine
* **[on_audio_query](https://pub.dev/packages/on_audio_query)** — Local device audio library scanner
* **[http](https://pub.dev/packages/http)** — Synchronized lyrics fetching via open APIs

## TODO
* **Add playlists**
* **Fix songs' artwork for showing multiple albums**
---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.
