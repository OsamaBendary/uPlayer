#include "mini_player_window.h"

#include <cstring>
#include <dlfcn.h>

#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

namespace {

// Method channel used twice: once on the main engine, once on the mini
// window's engine. Messages sent to one are forwarded to the other, which is
// how the two isolates talk.
constexpr char kMiniWindowChannel[] = "uplayer/mini_window";

// The Dart entrypoint argument that makes main() run the mini panel instead of
// the whole application (must match kMiniPlayerEntrypoint in
// lib/modules/player/mini_player/mini_player_service.dart).
constexpr char kMiniWindowEntrypoint[] = "uplayer-mini";

// The window's title is a stable handle for compositor-side helpers (the
// Hyprland fallback finds the window by it).
constexpr char kMiniWindowTitle[] = "uPlayer Mini Player";

constexpr char kMiniWindowNamespace[] = "uplayer-mini";
constexpr int kMiniWindowWidth = 380;
constexpr int kMiniWindowHeight = 128;
constexpr int kMiniWindowMargin = 16;

// ---------------------------------------------------------------------------
// gtk-layer-shell, loaded at run time
// ---------------------------------------------------------------------------
// The library is optional: when it is missing, or the session is not a Wayland
// compositor with support for layer surfaces, the mini window stays an
// ordinary floating window and the Dart side asks the compositor to keep it
// floating and on top instead. Loading it dynamically keeps the build free of
// a dependency that most machines cannot provide.

enum LayerShellEdge {
  kLayerShellEdgeLeft = 0,
  kLayerShellEdgeRight,
  kLayerShellEdgeTop,
  kLayerShellEdgeBottom,
};

enum LayerShellLayer {
  kLayerShellLayerBackground = 0,
  kLayerShellLayerBottom,
  kLayerShellLayerTop,
  kLayerShellLayerOverlay,
};

enum LayerShellKeyboardMode {
  kLayerShellKeyboardNone = 0,
  kLayerShellKeyboardExclusive,
  kLayerShellKeyboardOnDemand,
};

struct LayerShellApi {
  bool loaded = false;
  void (*init_for_window)(GtkWindow*) = nullptr;
  gboolean (*is_supported)() = nullptr;
  void (*set_namespace)(GtkWindow*, const char*) = nullptr;
  void (*set_layer)(GtkWindow*, LayerShellLayer) = nullptr;
  void (*set_anchor)(GtkWindow*, LayerShellEdge, gboolean) = nullptr;
  void (*set_margin)(GtkWindow*, LayerShellEdge, int) = nullptr;
  void (*set_keyboard_mode)(GtkWindow*, LayerShellKeyboardMode) = nullptr;
  void (*set_exclusive_zone)(GtkWindow*, int) = nullptr;
};

LayerShellApi g_layer_shell;

template <typename T>
void load_symbol(void* handle, const char* name, T* out) {
  void* symbol = dlsym(handle, name);
  if (symbol == nullptr) return;
  static_assert(sizeof(T) == sizeof(void*), "functions load into pointers");
  std::memcpy(out, &symbol, sizeof(void*));
}

void load_layer_shell() {
  static bool attempted = false;
  if (attempted) return;
  attempted = true;

  void* handle = dlopen("libgtk-layer-shell.so.0", RTLD_NOW | RTLD_LOCAL);
  if (handle == nullptr) {
    handle = dlopen("libgtk-layer-shell.so", RTLD_NOW | RTLD_LOCAL);
  }
  if (handle == nullptr) return;

  load_symbol(handle, "gtk_layer_init_for_window", &g_layer_shell.init_for_window);
  load_symbol(handle, "gtk_layer_is_supported", &g_layer_shell.is_supported);
  load_symbol(handle, "gtk_layer_set_namespace", &g_layer_shell.set_namespace);
  load_symbol(handle, "gtk_layer_set_layer", &g_layer_shell.set_layer);
  load_symbol(handle, "gtk_layer_set_anchor", &g_layer_shell.set_anchor);
  load_symbol(handle, "gtk_layer_set_margin", &g_layer_shell.set_margin);
  load_symbol(handle, "gtk_layer_set_keyboard_mode", &g_layer_shell.set_keyboard_mode);
  load_symbol(handle, "gtk_layer_set_exclusive_zone", &g_layer_shell.set_exclusive_zone);

  g_layer_shell.loaded = g_layer_shell.init_for_window != nullptr &&
                         g_layer_shell.is_supported != nullptr &&
                         g_layer_shell.set_anchor != nullptr &&
                         g_layer_shell.set_layer != nullptr &&
                         g_layer_shell.set_margin != nullptr;
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

FlMethodChannel* g_main_channel = nullptr;
GtkWindow* g_main_window = nullptr;
FlMethodChannel* g_window_channel = nullptr;
GtkWindow* g_window = nullptr;
bool g_layer_shell_active = false;
const char* g_layer_shell_reason = "lib-missing";

void send_to_main(const char* method, FlValue* args) {
  if (g_main_channel == nullptr) return;
  fl_method_channel_invoke_method(g_main_channel, method, args, nullptr, nullptr,
                                  nullptr);
}

void send_to_window(const char* method, FlValue* args) {
  if (g_window_channel == nullptr) return;
  fl_method_channel_invoke_method(g_window_channel, method, args, nullptr,
                                  nullptr, nullptr);
}

void window_method_call(FlMethodChannel* channel, FlMethodCall* method_call,
                        gpointer user_data);

// ---------------------------------------------------------------------------
// Window lifecycle
// ---------------------------------------------------------------------------

void window_destroyed(GtkWidget* widget, gpointer user_data) {
  g_window = nullptr;
  g_clear_object(&g_window_channel);
  g_layer_shell_active = false;

  // The compositor took the window away; the shell has to forget it so a
  // later toggle builds a fresh one.
  g_autoptr(FlValue) message = fl_value_new_map();
  fl_value_set_string_take(message, "type", fl_value_new_string("closed"));
  send_to_main("message", message);
}

// Parks the window in the top-right corner of the primary monitor. Only
// meaningful on X11 (Wayland ignores it); the Hyprland fallback repositions
// the window from the Dart side.
void place_window_at_top_right(GtkWindow* window) {
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  if (monitor == nullptr && gdk_display_get_n_monitors(display) > 0) {
    monitor = gdk_display_get_monitor(display, 0);
  }
  if (monitor == nullptr) return;

  GdkRectangle geometry = {};
  gdk_monitor_get_geometry(monitor, &geometry);
  gtk_window_move(window,
                  geometry.x + geometry.width - kMiniWindowWidth - kMiniWindowMargin,
                  geometry.y + kMiniWindowMargin);
}

// Turns [window] into a layer surface before it is realized, when the session
// can host one. Returns false (and records why) when it cannot.
bool attach_layer_shell(GtkWindow* window) {
  load_layer_shell();
  if (!g_layer_shell.loaded) {
    g_layer_shell_reason = "lib-missing";
    return false;
  }

  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  if (!GDK_IS_WAYLAND_DISPLAY(display)) {
    g_layer_shell_reason = "not-wayland";
    return false;
  }
  if (!g_layer_shell.is_supported()) {
    g_layer_shell_reason = "unsupported";
    return false;
  }

  g_layer_shell.init_for_window(window);
  g_layer_shell.set_namespace(window, kMiniWindowNamespace);
  g_layer_shell.set_layer(window, kLayerShellLayerTop);
  g_layer_shell.set_anchor(window, kLayerShellEdgeTop, TRUE);
  g_layer_shell.set_anchor(window, kLayerShellEdgeRight, TRUE);
  g_layer_shell.set_anchor(window, kLayerShellEdgeLeft, FALSE);
  g_layer_shell.set_anchor(window, kLayerShellEdgeBottom, FALSE);
  g_layer_shell.set_margin(window, kLayerShellEdgeTop, kMiniWindowMargin);
  g_layer_shell.set_margin(window, kLayerShellEdgeRight, kMiniWindowMargin);
  g_layer_shell.set_keyboard_mode(window, kLayerShellKeyboardOnDemand);
  // Never reserve space for the panel and never let other margins displace it.
  g_layer_shell.set_exclusive_zone(window, -1);

  g_layer_shell_reason = "ok";
  return true;
}

void create_window() {
  GtkWindow* window = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));
  gtk_window_set_title(window, kMiniWindowTitle);
  gtk_window_set_default_size(window, kMiniWindowWidth, kMiniWindowHeight);
  gtk_window_set_resizable(window, FALSE);
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_skip_pager_hint(window, TRUE);
  gtk_window_set_keep_above(window, TRUE);
  gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_UTILITY);
  gtk_window_set_gravity(window, GDK_GRAVITY_NORTH_EAST);

  // The panel paints its own rounded chrome; the window itself has to be RGBA
  // for the corners around it to really be transparent.
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  GdkScreen* screen = gtk_widget_get_screen(GTK_WIDGET(window));
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr) {
    gtk_widget_set_visual(GTK_WIDGET(window), visual);
  }

  g_layer_shell_active = false;
  if (g_getenv("UPLAYER_MINI_NO_LAYER_SHELL") != nullptr) {
    // Debug switch: exercise the ordinary-window fallback on machines that do
    // have gtk-layer-shell installed.
    g_layer_shell_reason = "debug-floating";
  } else {
    g_layer_shell_active = attach_layer_shell(window);
  }
  if (!g_layer_shell_active) {
    place_window_at_top_right(window);
  }

  // The panel is painted by a second engine running the same bundle: main()
  // branches on the entrypoint argument and boots only the mini player UI.
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  const char* arguments[] = {kMiniWindowEntrypoint, nullptr};
  fl_dart_project_set_dart_entrypoint_arguments(
      project, const_cast<char**>(arguments));

  FlView* view = fl_view_new(project);
  GdkRGBA transparent;
  gdk_rgba_parse(&transparent, "#00000000");
  fl_view_set_background_color(view, &transparent);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // gtk-layer-shell sizes the surface from the window's content: without a
  // minimum the panel's window grows past the size asked for below. Pinning
  // the view keeps the panel at its designed size.
  gtk_widget_set_size_request(GTK_WIDGET(view), kMiniWindowWidth,
                              kMiniWindowHeight);
  gtk_widget_show(GTK_WIDGET(view));

  g_window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      kMiniWindowChannel, FL_METHOD_CODEC(fl_standard_method_codec_new()));
  fl_method_channel_set_method_call_handler(g_window_channel,
                                            window_method_call, nullptr,
                                            nullptr);

  g_signal_connect(window, "destroy", G_CALLBACK(window_destroyed), nullptr);
  g_window = window;
}

void show_window() {
  if (g_window == nullptr) {
    create_window();
  }
  if (g_window == nullptr) return;

  gtk_widget_show(GTK_WIDGET(g_window));
  if (!g_layer_shell_active) {
    // A layer surface already sits above everything; an ordinary window has to
    // be raised explicitly.
    gtk_window_present(g_window);
  }
}

void hide_window() {
  if (g_window != nullptr) {
    gtk_widget_hide(GTK_WIDGET(g_window));
  }
}

// ---------------------------------------------------------------------------
// Channels
// ---------------------------------------------------------------------------

void window_method_call(FlMethodChannel* channel, FlMethodCall* method_call,
                        gpointer user_data) {
  const char* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "message") == 0) {
    // Everything the panel has to say (playback commands, "ready", artwork
    // requests) is a payload for the shell isolate.
    send_to_main("message", fl_method_call_get_args(method_call));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

void main_method_call(FlMethodChannel* channel, FlMethodCall* method_call,
                      gpointer user_data) {
  const char* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "show") == 0) {
    show_window();
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "layerShell",
                             fl_value_new_bool(g_layer_shell_active));
    fl_value_set_string_take(result, "layerShellReason",
                             fl_value_new_string(g_layer_shell_reason));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "hide") == 0) {
    hide_window();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "close") == 0) {
    // Tearing the second engine down while the shell keeps rendering crashes
    // the shared GDK/EGL state on this stack, so "close" only unmaps the
    // panel: the engine idles until the next show (or until the app quits).
    hide_window();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "raise") == 0) {
    if (g_main_window != nullptr) {
      gtk_window_present(g_main_window);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "message") == 0) {
    send_to_window("message", fl_method_call_get_args(method_call));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

}  // namespace

void mini_player_window_register(FlEngine* main_engine, GtkWindow* main_window) {
  g_main_window = main_window;
  g_clear_object(&g_main_channel);
  g_main_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(main_engine), kMiniWindowChannel,
      FL_METHOD_CODEC(fl_standard_method_codec_new()));
  fl_method_channel_set_method_call_handler(g_main_channel, main_method_call,
                                            nullptr, nullptr);
}

void mini_player_window_shutdown() {
  // Destroying the panel here would take its second engine down while GTK is
  // still dispatching frames, which crashes the shared GDK state. Unmapping
  // is enough: the process exits right after the main window goes away.
  hide_window();
  g_clear_object(&g_main_channel);
  g_main_window = nullptr;
}
