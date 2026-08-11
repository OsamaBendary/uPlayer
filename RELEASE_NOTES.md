# Release Notes — u_player v2.0.0

## What's New

### Go-Powered Download Engine
* **Native Download Backend**: A Go (gomobile) backend now handles all streaming-provider downloads in the background — faster, more reliable, and tagged with metadata as files land on disk.
* **Lossless FLAC Downloads**: Choose FLAC 16/44 or FLAC 24-bit quality; the engine automatically prioritizes lossless-capable providers (Tidal, Qobuz, Deezer, Amazon, Apple Music, Pandora) over lossy-only ones like SoundCloud and YouTube Music.

### Extension Store & Providers
* **In-App Extension Store**: Install streaming-provider extensions (Tidal, Qobuz, Deezer, SoundCloud, YouTube Music, ...) directly from Settings → Extension Store & Providers.
* **Zero-Login Verification**: Browser-based authorization that deep-links straight back into uPlayer (`spotiflac://`/`uplayer://` session grant) — no credentials typed in-app.

### Download Destination Control
* **Pick Your Folder**: Downloads now land in `Music/uPlayer` on public storage when "All files access" is granted (requested automatically on Android 10+), or any folder you choose — with permission guidance built in.

### Customization Screen (Settings → Customization)
* **Song Tap Behavior**: Choose whether tapping a song opens the full player or just plays it in the mini player (the mini player tap then opens the full player).
* **Seek Bar Style**: Move the waveform/normal seek bar toggle here — it now persists across restarts.
* **Artwork Style**: Switch between five player artwork looks — normal square art, Picture Disc, Classic Silver CD, Jewel Case, and Minimal Dark CD — all spinning while playing.

### Player Screen Polish
* **Fixed Scaling**: The player layout no longer shrinks to fit — artwork flexes to fill available space while controls and buttons keep their intended size.
* **Smooth Waveform**: The waveform seek bar now interpolates between position updates, gliding smoothly instead of jumping column-by-column.
* **Messages Above the Mini Player**: Every snackbar in the app now pops up above the mini player instead of behind it.

---

## Changes Since v1.3.0

* CD-player artwork styles (Picture Disc / Silver / Jewel Case / Minimal Dark), all switchable from Customization.
* Persisted seek bar & artwork preferences (previously reset on every launch).
* All snackbars routed above the mini player + navigation bar.
* Bug fixes across download folder selection, verification redirects, and bridge availability detection.

---

## v1.2.0 & Earlier

* **Ultra-Smooth Waveform Seekbar**: Proportional touch scrubbing, RMS+Peak volume analysis, tap-to-seek.
* **Centered Popup Dialogs**: Clean, dark, centered alert dialogs throughout.
* **"Play Once" Repeat Mode** with amber badge indicator.
* **Automatic GitHub Release Updates**.
* **Background Playback & Battery Optimizations** for Honor, Xiaomi, and Samsung devices.
* **Playlists System**: custom cover art picker, searchable song picker.
* **Pinned Liked Songs** card in the Playlists tab.
* **Listening Stats**: ranked top songs/artists/albums, play counts at 50% threshold.
* **Glassy Floating Navigation Bar** with 4 tabs.
