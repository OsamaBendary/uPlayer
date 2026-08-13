package com.uplayer.u_player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.embedding.engine.FlutterEngine
import org.json.JSONArray
import java.lang.reflect.Method
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Bridges Dart to the gomobile-bound `go_backend` library (gobackend.aar).
 *
 * The Go class is resolved with reflection so the app still builds and runs
 * without the AAR present (downloads then fall back to the Dart-side path).
 * Heavy calls (downloads, repo fetches, extension loads) run on a background
 * executor — `DownloadByStrategy` blocks until the track finishes, so it must
 * never run on the platform main thread.
 */
class GoBackendBridge(private val context: Context) : MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.uplayer.u_player/go_backend"
        private const val GO_CLASS = "gobackend.Gobackend"

        // Reported to the Go extension system. Must be >= the highest
        // min_app_version in the store (4.7.0) or manifest gates reject installs;
        // "4.8.5" matches the SpotiFLAC mobile lineage this backend is forked from.
        private const val APP_VERSION = "4.8.5"

        private var backendChannel: MethodChannel? = null

        fun register(engine: FlutterEngine, context: Context) {
            val bridge = GoBackendBridge(context)
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            backendChannel = channel
            channel.setMethodCallHandler(bridge)
        }

        /**
         * Handles a `uplayer://session-grant?...` deep link produced by the
         * provider verification page: feeds the grant into the Go extension
         * system (`setExtensionSessionGrantByID` + `completeGrant`), then tells
         * Dart so in-flight downloads can resume automatically.
         */
        fun handleSessionGrantUri(uriString: String?) {
            if (uriString.isNullOrEmpty()) return
            val uri = Uri.parse(uriString)
            if (uri.host != "session-grant") return
            val code = (uri.getQueryParameter("grant")
                ?: uri.getQueryParameter("code"))?.trim().orEmpty()
            if (code.isEmpty()) return
            val extensionId = uri.getQueryParameter("state")?.trim().orEmpty()
            if (extensionId.isEmpty()) return

            Executors.newSingleThreadExecutor().execute {
                var success = false
                try {
                    val clazz = Class.forName(GO_CLASS)
                    clazz.getMethod("setExtensionSessionGrantByID", String::class.java, String::class.java)
                        .invoke(null, extensionId, code)
                    val raw = clazz.getMethod("invokeExtensionActionJSON", String::class.java, String::class.java)
                        .invoke(null, extensionId, "completeGrant")
                    success = raw?.toString()?.contains("\"success\":true") == true
                } catch (e: Throwable) {
                    // fall through: report failure
                }
                Handler(Looper.getMainLooper()).post {
                    val payload = mapOf(
                        "extension_id" to extensionId,
                        "success" to success,
                    )
                    try {
                        backendChannel?.invokeMethod("extensionSessionGrantCompleted", payload)
                    } catch (e: Throwable) {
                        // Dart side may not be listening yet
                    }
                }
            }
        }
    }

    private val executor: ExecutorService = Executors.newFixedThreadPool(3)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var goClass: Class<*>? = null

    private var appVersionSet = false

    // Methods that must return instantly; routed to the executor only when
    //    they actually hit Go code.
    private val goMethodNames = setOf(
        "initExtensionSystem",
        "initExtensionRepo",
        "setDownloadDirectory",
        "setMetadataLanguage",
        "setNetworkCompatibilityOptions",
        "setAllowPrivateNetwork",
        "loadExtensionsFromDir",
        "loadExtensionFromPath",
        "unloadExtension",
        "removeExtension",
        "getInstalledExtensions",
        "setExtensionEnabled",
        "getExtensionPendingAuth",
        "setExtensionSessionGrantByID",
        "invokeExtensionAction",
        "setProviderPriority",
        "getProviderPriority",
        "setMetadataProviderPriority",
        "getMetadataProviderPriority",
        "setFallbackProviders",
        "setRepoRegistryUrl",
        "getRepoRegistryUrl",
        "clearRepoRegistryUrl",
        "getRepoExtensions",
        "getRepoCategories",
        "downloadRepoExtension",
        "downloadByStrategy",
        "getAllDownloadProgress",
        "getAllDownloadProgressDelta",
        "initItemProgress",
        "clearItemProgress",
        "cancelDownload",
        "resetDownloadCancel",
        "runPostProcessingV2",
        "editFileMetadata",
        "releaseMemory",
        "releaseMemoryUnderPressure",
        "cleanupConnections",
        "cleanupExtensions",
        "getGoLogsSince",
        "getGoRuntimeMetrics",
        "getLyricsLRC",
    )

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "getAppDirs") {
            result.success(appDirs())
            return
        }
        if (!goMethodNames.contains(call.method)) {
            android.util.Log.w(
                "GoBackendBridge",
                "notImplemented for unknown method: ${call.method}",
            )
            result.notImplemented()
            return
        }
        execute(call.method, call, result)
    }

    private fun execute(method: String, call: MethodCall, result: Result) {
        executor.execute {
            try {
                val value = dispatch(method, call)
                mainHandler.post { result.success(value) }
            } catch (e: ClassNotFoundException) {
                val message = if (e.message.isNullOrEmpty()) GO_CLASS else e.message
                mainHandler.post { result.error("missing_go_backend", message, null) }
            } catch (e: NoSuchMethodException) {
                val message = "Bridge wiring bug: ${e.message ?: "missing method for $method"}"
                mainHandler.post { result.error("no_such_method", message, null) }
            } catch (e: Throwable) {
                val message = e.message ?: e.toString()
                mainHandler.post { result.error("go_backend_error", message, null) }
            }
        }
    }

    @Throws(Throwable::class)
    private fun dispatch(method: String, call: MethodCall): Any? {
        return when (method) {
            "initExtensionSystem" -> go(
                "InitExtensionSystem",
                call.requireString("extensions_dir"),
                call.requireString("data_dir"),
            )
            "initExtensionRepo" -> go("InitExtensionRepoJSON", call.requireString("cache_dir"))
            "setDownloadDirectory" -> {
                val path = call.requireString("path")
                go("SetDownloadDirectory", path)
                go("AllowDownloadDir", path)
                null
            }
            "setMetadataLanguage" -> {
                go("SetMetadataLanguage", call.requireString("tag"))
                null
            }
            "setNetworkCompatibilityOptions" -> {
                go(
                    "SetNetworkCompatibilityOptions",
                    call.requireBool("allow_http"),
                    call.requireBool("insecure_tls"),
                )
                null
            }
            "setAllowPrivateNetwork" -> {
                go("SetAllowPrivateNetwork", call.requireBool("allowed"))
                null
            }
            "loadExtensionsFromDir" -> jsonResult(go("LoadExtensionsFromDir", call.requireString("dir_path")))
            "loadExtensionFromPath" -> jsonResult(go("LoadExtensionFromPath", call.requireString("file_path")))
            "unloadExtension" -> {
                go("UnloadExtensionByID", call.requireString("extension_id"))
                null
            }
            "removeExtension" -> {
                go("RemoveExtensionByID", call.requireString("extension_id"))
                null
            }
            "getInstalledExtensions" -> jsonResult(go("GetInstalledExtensions"))
            "getExtensionPendingAuth" -> jsonResult(go("GetExtensionPendingAuthJSON", call.requireString("extension_id")))
            "setExtensionSessionGrantByID" -> {
                go(
                    "SetExtensionSessionGrantByID",
                    call.requireString("extension_id"),
                    call.requireString("grant"),
                )
                null
            }
            "invokeExtensionAction" -> jsonResult(
                go(
                    "InvokeExtensionActionJSON",
                    call.requireString("extension_id"),
                    call.requireString("action"),
                ),
            )
            "setExtensionEnabled" -> {
                go(
                    "SetExtensionEnabledByID",
                    call.requireString("extension_id"),
                    call.requireBool("enabled"),
                )
                null
            }
            "setProviderPriority" -> {
                go("SetProviderPriorityJSON", jsonArray(call.requireList("priority")))
                null
            }
            "getProviderPriority" -> jsonResult(go("GetProviderPriorityJSON"))
            "setMetadataProviderPriority" -> {
                go("SetMetadataProviderPriorityJSON", jsonArray(call.requireList("priority")))
                null
            }
            "getMetadataProviderPriority" -> jsonResult(go("GetMetadataProviderPriorityJSON"))
            "setFallbackProviders" -> {
                val ids = call.argument<List<String>>("provider_ids") ?: emptyList()
                go("SetExtensionFallbackProviderIDsJSON", jsonArray(ids))
                null
            }
            "setRepoRegistryUrl" -> {
                go("SetRepoRegistryURLJSON", call.requireString("registry_url"))
                null
            }
            "getRepoRegistryUrl" -> stringValue(go("GetRepoRegistryURLJSON"))
            "clearRepoRegistryUrl" -> {
                go("ClearRepoRegistryURLJSON")
                null
            }
            "getRepoExtensions" -> jsonResult(go("GetRepoExtensionsJSON", call.requireBool("force_refresh")))
            "getRepoCategories" -> jsonResult(go("GetRepoCategoriesJSON"))
            "downloadRepoExtension" -> stringValue(
                go("DownloadRepoExtensionJSON", call.requireString("extension_id"), call.requireString("dest_dir")),
            )
            "downloadByStrategy" -> jsonResult(go("DownloadByStrategy", call.requireString("request_json")))
            "getAllDownloadProgress" -> jsonResult(go("GetAllDownloadProgress"))
            "getAllDownloadProgressDelta" -> {
                val sinceSeq = (call.argument<Number>("since_seq") ?: 0L).toLong()
                val raw = go("GetAllDownloadProgressDelta", sinceSeq)
                if (raw == null || raw.toString().isEmpty()) null else jsonResult(raw)
            }
            "initItemProgress" -> {
                go("InitItemProgress", call.requireString("item_id"))
                null
            }
            "clearItemProgress" -> {
                go("ClearItemProgress", call.requireString("item_id"))
                null
            }
            "cancelDownload" -> {
                go("CancelDownload", call.requireString("item_id"))
                null
            }
            "resetDownloadCancel" -> {
                go("ResetDownloadCancel", call.requireString("item_id"))
                null
            }
            "runPostProcessingV2" -> jsonResult(
                go(
                    "RunPostProcessingV2JSON",
                    call.requireString("input"),
                    call.requireString("metadata"),
                ),
            )
            "editFileMetadata" -> jsonResult(
                go(
                    "EditFileMetadata",
                    call.requireString("file_path"),
                    call.requireString("metadata_json"),
                ),
            )
            "releaseMemory" -> {
                go("ReleaseMemory")
                null
            }
            "releaseMemoryUnderPressure" -> {
                go("ReleaseMemoryUnderPressure")
                null
            }
            "cleanupConnections" -> {
                go("CleanupConnections")
                null
            }
            "cleanupExtensions" -> {
                go("CleanupExtensions")
                null
            }
            "getGoLogsSince" -> jsonResult(go("GetLogsSince", (call.argument<Number>("index") ?: 0L).toLong()))
            "getGoRuntimeMetrics" -> jsonResult(go("GetRuntimeMetricsJSON"))
            "getLyricsLRC" -> stringValue(
                go(
                    "GetLyricsLRC",
                    call.requireString("spotify_id"),
                    call.requireString("track_name"),
                    call.requireString("artist_name"),
                    call.requireString("file_path"),
                    (call.argument<Number>("duration_ms") ?: 0L).toLong(),
                ),
            )
            else -> throw IllegalArgumentException("Unhandled bridge method: $method")
        }
    }

    /** Reflective call into `gobackend.Gobackend`. Throws when the AAR is missing. */
    @Throws(Throwable::class)
    private fun go(methodName: String, vararg args: Any?): Any? {
        val clazz = goClass ?: Class.forName(GO_CLASS).also { goClass = it }
        if (!appVersionSet) {
            appVersionSet = true
            try {
                clazz.getMethod("setAppVersion", String::class.java)
                    .invoke(null, APP_VERSION)
            } catch (e: Throwable) {
                appVersionSet = false
            }
        }
        // gomobile generates camelCase Java names (initExtensionSystem, ...)
        // while the dispatch table above uses Go-style PascalCase; Java method
        // lookup is case-sensitive, so convert before reflecting.
        val javaName = methodName.replaceFirstChar { it.lowercaseChar() }
        val types = args.map { arg ->
            when (arg) {
                is String -> String::class.java
                is Boolean -> java.lang.Boolean.TYPE
                is Long -> java.lang.Long.TYPE
                is Int -> java.lang.Integer.TYPE
                else -> arg?.javaClass ?: Any::class.java
            }
        }.toTypedArray()
        val method: Method = clazz.getMethod(javaName, *types)
        return method.invoke(null, *args)
    }

    private fun appDirs(): Map<String, String> {
        val filesDir = context.filesDir?.path ?: ""
        val cacheDir = context.cacheDir?.path ?: ""
        val externalMusic = context.getExternalFilesDir(null)?.path?.let { "$it/Music" } ?: ""
        return mapOf(
            "support_dir" to filesDir,
            "cache_dir" to cacheDir,
            "default_download_dir" to externalMusic,
        )
    }

    private fun jsonArray(items: List<String>): String = JSONArray(items).toString()

    private fun jsonResult(raw: Any?): String? = raw?.toString()?.takeIf { it.isNotEmpty() }

    private fun stringValue(raw: Any?): String = raw?.toString() ?: ""

    private fun MethodCall.requireString(key: String): String =
        argument<String>(key) ?: throw IllegalArgumentException("Missing string argument '$key'")

    private fun MethodCall.requireBool(key: String): Boolean =
        argument<Boolean>(key) ?: throw IllegalArgumentException("Missing boolean argument '$key'")

    @Suppress("UNCHECKED_CAST")
    private fun MethodCall.requireList(key: String): List<String> =
        argument<List<String>>(key) ?: throw IllegalArgumentException("Missing list argument '$key'")
}