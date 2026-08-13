# Release Notes — u_player v2.1.0

## What's New

### Queue, Revamped
* **Dedicated Queue Screen**: Open it from the mini player's queue button. See the whole playback list, tap any song to jump to it, and swipe a row left to remove it from the queue (the current song is highlighted).
* **Swipe to Add to Queue**: In the library, search results, and every song list, swipe a song left to reveal a green "Add to queue" layer — release past the halfway point and it's queued instantly with a confirmation snackbar. The row snaps back in place; your list is never disturbed.
* **Smarter Swipes**: Queuing a song never pops the screen you're on anymore, and screen-level swipe-back (header areas) still works exactly as before.

### Cover Art Search
* **Fix Missing Artwork**: Song options now offer "Search cover" — an iTunes-based cover search finds the right album art for tracks with missing artwork and attaches it.

### Downloads
* **FFmpeg Post-Processing**: Downloads now run through the same FFmpeg conversion pipeline as the desktop SpotiFLAC app — M4A/DASH sources are converted to FLAC (or the requested lossy format) and metadata is tagged as files land on disk.
* **Quality-aware Source Ordering**: Download quality selection accounts for per-provider capabilities when picking the source.

---

## Bug Fixes

* **"Have to tap twice" song rows**: A drag recognizer competing with row taps silently swallowed the first tap; rows now use a raw listener so every tap fires first time.
* **Red screen on mini player**: The mini player's queue button could crash the app when the player screen wasn't open (a tooltip rendered outside the navigator). Gone.
* **Swipe-down on the player** dismisses cleanly without a crash.
* **Queue state handling** hardened against audio-player edge cases when removing sources.

---

## v2.0.0

* Go-powered download engine with lossless FLAC downloads (Tidal, Qobuz, Deezer, Amazon, Apple Music, Pandora prioritization).
* In-app extension store with zero-login browser verification.
* Download destination control (public Music/uPlayer folder with all-files-access guidance).
* Customization screen: song tap behavior, seek bar style, five artwork styles (Picture Disc / Classic Silver CD / Jewel Case / Minimal Dark CD), all persisted.
* Player screen polish: fixed scaling, smooth waveform interpolation, snackbars routed above the mini player.

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
