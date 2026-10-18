#ifndef RUNNER_MINI_PLAYER_WINDOW_H_
#define RUNNER_MINI_PLAYER_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// The desktop mini player runs in its own always-on-top window with its own
// Flutter engine. The window is created here (not by Dart) because it has to
// exist *before* it is realized: gtk-layer-shell, when available, turns it
// into a Wayland layer surface anchored to the top-right corner, and that
// decision cannot be made once the window is already mapped.
//
// Installs the bridge on [main_engine]'s messenger: Dart drives the window
// through the "uplayer/mini_window" method channel, using `show` / `hide` /
// `close` / `raise` for the window itself and `message` for arbitrary payloads
// (playback snapshots, commands) that are relayed verbatim to the window's own
// engine and back. Keeping every piece of state in the main isolate means the
// two engines share nothing but that channel.
void mini_player_window_register(FlEngine* main_engine, GtkWindow* main_window);

// Called when the application's main window goes away: the mini player cannot
// outlive it (there would be no shell left to talk to, and the application
// quits with its last window). Parks the panel instead of destroying it so the
// second engine is never torn down while GTK is still dispatching frames.
void mini_player_window_shutdown(void);

#endif  // RUNNER_MINI_PLAYER_WINDOW_H_
