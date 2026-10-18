#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

// Method channel used to forward `uplayer://` / `spotiflac://` deep links
// (provider verification pages) to Dart, which feeds them into the Go
// extension session exchange. Mirrors the Android intent-filter path.
static constexpr char kDeepLinkChannel[] =
    "com.uplayer.u_player/deep_links";

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* deep_link_channel;
  // Deep links that arrived before Dart started listening (cold start); they
  // are handed over when Dart calls `takePendingUris`.
  GPtrArray* pending_deep_links;
  gboolean drain_ready;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static gboolean is_deep_link_uri(const gchar* uri) {
  return uri != nullptr &&
         (g_str_has_prefix(uri, "uplayer://") ||
          g_str_has_prefix(uri, "spotiflac://"));
}

// Queues/forwards one deep link to Dart.
static void my_application_send_deep_link(MyApplication* self,
                                          const gchar* uri) {
  if (!is_deep_link_uri(uri)) return;

  if (self->pending_deep_links == nullptr) {
    self->pending_deep_links =
        g_ptr_array_new_with_free_func(static_cast<GDestroyNotify>(g_free));
  }

  // Until Dart has drained the queue once, its method-call handler is not
  // guaranteed to be attached — park the URI instead of pushing.
  if (!self->drain_ready || self->deep_link_channel == nullptr) {
    g_ptr_array_add(self->pending_deep_links, g_strdup(uri));
    return;
  }

  g_autoptr(FlValue) args = fl_value_new_string(uri);
  fl_method_channel_invoke_method(self->deep_link_channel, "sessionGrantUri",
                                  args, nullptr, nullptr, nullptr);
}

// Handles Dart -> native calls on the deep-link channel (currently only
// `takePendingUris`, which both drains the backlog and marks the listener as
// ready).
static void deep_link_method_call_cb(FlMethodChannel* channel,
                                     FlMethodCall* method_call,
                                     gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "takePendingUris") == 0) {
    self->drain_ready = TRUE;
    g_autoptr(FlValue) uris = fl_value_new_list();
    if (self->pending_deep_links != nullptr) {
      for (guint i = 0; i < self->pending_deep_links->len; i++) {
        fl_value_append_take(
            uris,
            fl_value_new_string(static_cast<const gchar*>(
                g_ptr_array_index(self->pending_deep_links, i))));
      }
      g_ptr_array_set_size(self->pending_deep_links, 0);
    }
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(static_cast<FlValue*>(uris)));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // Single-window app: a second activation just raises the existing window.
  if (self->window != nullptr) {
    gtk_window_present(self->window);
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "uPlayer");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "uPlayer");
  }

  // Desktop layouts want a wide canvas (album grid + side-by-side player),
  // so the window opens near 1160x700 and shrinks to fit the monitor's work
  // area when the screen is smaller than that.
  gint target_width = 1160;
  gint target_height = 700;
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  if (monitor == nullptr && gdk_display_get_n_monitors(display) > 0) {
    monitor = gdk_display_get_monitor(display, 0);
  }
  if (monitor != nullptr) {
    GdkRectangle workarea = {};
    gdk_monitor_get_workarea(monitor, &workarea);
    const gint max_width = workarea.width - 80;
    const gint max_height = workarea.height - 60;
    if (max_width > 0 && target_width > max_width) {
      target_width = max_width;
    }
    if (max_height > 0 && target_height > max_height) {
      target_height = max_height;
    }
  }
  gtk_window_set_default_size(window, target_width, target_height);
  GdkGeometry geometry = {};
  geometry.min_width = MIN(760, target_width);
  geometry.min_height = MIN(480, target_height);
  gtk_window_set_geometry_hints(window, nullptr, &geometry, GDK_HINT_MIN_SIZE);

  self->window = window;
  g_object_add_weak_pointer(G_OBJECT(window),
                            reinterpret_cast<gpointer*>(&self->window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Map the window right away instead of waiting for Flutter's first frame.
  // On this machine the first frame can occasionally stall (GPU driver), and
  // a GtkApplication whose only window is never mapped just quits, which made
  // launches fail roughly half the time with no error at all.
  gtk_widget_show(GTK_WIDGET(window));
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Deep-link channel (Dart drains queued URIs once it is listening).
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->deep_link_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      kDeepLinkChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->deep_link_channel, deep_link_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::open (deep links / files opened by the desktop).
static void my_application_open(GApplication* application, GFile** files,
                                gint n_files, const gchar* hint) {
  MyApplication* self = MY_APPLICATION(application);

  for (gint i = 0; i < n_files; i++) {
    g_autofree gchar* uri = g_file_get_uri(files[i]);
    if (is_deep_link_uri(uri)) {
      my_application_send_deep_link(self, uri);
    }
  }

  // A URI-only launch never triggers `activate`, so create the window here.
  if (self->window == nullptr) {
    my_application_activate(application);
  } else {
    gtk_window_present(self->window);
  }
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  // Deep links arrive as `uplayer://session-grant?...` arguments.
  g_autoptr(GPtrArray) deep_link_files =
      g_ptr_array_new_with_free_func(g_object_unref);
  for (gchar** arg = *arguments + 1; *arg != nullptr; arg++) {
    if (is_deep_link_uri(*arg)) {
      g_ptr_array_add(deep_link_files, g_file_new_for_uri(*arg));
    }
  }

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  if (deep_link_files->len > 0) {
    // Routes to this process, or to the already-running instance over D-Bus.
    g_application_open(application,
                       reinterpret_cast<GFile**>(deep_link_files->pdata),
                       deep_link_files->len, "");
  } else {
    g_application_activate(application);
  }
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_pointer(&self->pending_deep_links, g_ptr_array_unref);
  g_clear_object(&self->deep_link_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // Single-instance app: G_APPLICATION_HANDLES_OPEN lets a later launch with
  // a `uplayer://` URI forward it to the running instance over D-Bus.
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_OPEN, nullptr));
}
