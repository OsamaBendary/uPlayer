// Command uplayer_sidecar is the Linux desktop host process for the uPlayer
// Go backend.
//
// Android links the backend in as a gomobile AAR behind a Kotlin
// MethodChannel; Linux has no gomobile support, so the same package is
// compiled as a plain binary and spoken to over line-delimited JSON on
// stdin/stdout by `LinuxGoTransport` in the Flutter app.
//
// The method names, argument keys, result payloads and error codes mirror the
// Kotlin bridge (android/app/src/main/kotlin/com/uplayer/u_player/
// GoBackendBridge.kt) one-to-one, so the Dart side behaves identically on both
// platforms. Results that the Kotlin bridge returns as JSON strings
// (`jsonResult`) are stringified here too — the Dart decoder expects text.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"runtime/debug"
	"strings"
	"sync"

	gobackend "github.com/zarz/spotiflac_android/go_backend"
)

// Must be >= the highest min_app_version in the extension store (4.7.0) or
// manifest gates reject installs; matches the SpotiFLAC mobile lineage the
// backend is forked from (same value as the Kotlin bridge).
const appVersion = "4.8.5"

type request struct {
	ID     int64           `json:"id"`
	Method string          `json:"method"`
	Args   json.RawMessage `json:"args"`
}

type response struct {
	ID     int64       `json:"id"`
	Result interface{} `json:"result"`
}

type errorInfo struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type errorResponse struct {
	ID    int64     `json:"id"`
	Error errorInfo `json:"error"`
}

var (
	outMu      sync.Mutex
	protoOut   *os.File = os.Stdout
	handlersWG sync.WaitGroup
)

func writeLine(payload interface{}) {
	encoded, err := json.Marshal(payload)
	if err != nil {
		log.Printf("marshal response failed: %v", err)
		return
	}
	outMu.Lock()
	defer outMu.Unlock()
	if _, err := protoOut.Write(append(encoded, '\n')); err != nil {
		log.Printf("write response failed: %v", err)
	}
}

// ─── Argument helpers ───────────────────────────────────────────────────────

type args map[string]json.RawMessage

func (a args) raw(key string) (json.RawMessage, bool) {
	value, ok := a[key]
	if !ok || len(value) == 0 || string(value) == "null" {
		return nil, false
	}
	return value, true
}

func (a args) requiredString(key string) (string, error) {
	value, ok := a.raw(key)
	if !ok {
		return "", fmt.Errorf("missing string argument '%s'", key)
	}
	var str string
	if err := json.Unmarshal(value, &str); err != nil {
		return "", fmt.Errorf("argument '%s' is not a string: %w", key, err)
	}
	return str, nil
}

// optionalString returns the string argument or the zero value when absent.
func (a args) optionalString(key string) (string, error) {
	if _, ok := a.raw(key); !ok {
		return "", nil
	}
	return a.requiredString(key)
}

func (a args) requiredBool(key string) (bool, error) {
	value, ok := a.raw(key)
	if !ok {
		return false, fmt.Errorf("missing boolean argument '%s'", key)
	}
	var b bool
	if err := json.Unmarshal(value, &b); err != nil {
		return false, fmt.Errorf("argument '%s' is not a boolean: %w", key, err)
	}
	return b, nil
}

func (a args) optionalBool(key string) (bool, error) {
	if _, ok := a.raw(key); !ok {
		return false, nil
	}
	return a.requiredBool(key)
}

// int64Value accepts JSON numbers (and numeric strings, since Kotlin's
// `Number` arguments always arrived as Longs).
func (a args) int64Value(key string) (int64, error) {
	value, ok := a.raw(key)
	if !ok {
		return 0, nil
	}
	var n int64
	if err := json.Unmarshal(value, &n); err == nil {
		return n, nil
	}
	var f float64
	if err := json.Unmarshal(value, &f); err == nil {
		return int64(f), nil
	}
	var s string
	if err := json.Unmarshal(value, &s); err == nil {
		var parsed int64
		if _, err := fmt.Sscanf(strings.TrimSpace(s), "%d", &parsed); err == nil {
			return parsed, nil
		}
	}
	return 0, fmt.Errorf("argument '%s' is not a number", key)
}

// jsonText returns a JSON-encoded string argument. The Dart transport already
// JSON-encodes list/map arguments (Kotlin did the same with jsonArray()), so
// strings pass through as-is while real arrays/objects are re-encoded.
func (a args) jsonText(key string) (string, error) {
	value, ok := a.raw(key)
	if !ok {
		return "", nil
	}
	var str string
	if err := json.Unmarshal(value, &str); err == nil {
		return str, nil
	}
	return string(value), nil
}

// ─── Dispatch ───────────────────────────────────────────────────────────────

func dispatch(method string, a args) (interface{}, error) {
	switch method {
	case "initExtensionSystem":
		extensionsDir, err := a.requiredString("extensions_dir")
		if err != nil {
			return nil, err
		}
		dataDir, err := a.requiredString("data_dir")
		if err != nil {
			return nil, err
		}
		return nil, gobackend.InitExtensionSystem(extensionsDir, dataDir)

	case "initExtensionRepo":
		cacheDir, err := a.requiredString("cache_dir")
		if err != nil {
			return nil, err
		}
		return nil, gobackend.InitExtensionRepoJSON(cacheDir)

	case "setDownloadDirectory":
		path, err := a.requiredString("path")
		if err != nil {
			return nil, err
		}
		if err := gobackend.SetDownloadDirectory(path); err != nil {
			return nil, err
		}
		gobackend.AllowDownloadDir(path)
		return nil, nil

	case "setMetadataLanguage":
		tag, err := a.requiredString("tag")
		if err != nil {
			return nil, err
		}
		gobackend.SetMetadataLanguage(tag)
		return nil, nil

	case "setNetworkCompatibilityOptions":
		allowHTTP, err := a.requiredBool("allow_http")
		if err != nil {
			return nil, err
		}
		insecureTLS, err := a.requiredBool("insecure_tls")
		if err != nil {
			return nil, err
		}
		gobackend.SetNetworkCompatibilityOptions(allowHTTP, insecureTLS)
		return nil, nil

	case "setAllowPrivateNetwork":
		allowed, err := a.requiredBool("allowed")
		if err != nil {
			return nil, err
		}
		gobackend.SetAllowPrivateNetwork(allowed)
		return nil, nil

	// ─── Extensions ─────────────────────────────────────────────────────
	case "loadExtensionsFromDir":
		dir, err := a.requiredString("dir_path")
		if err != nil {
			return nil, err
		}
		raw, err := gobackend.LoadExtensionsFromDir(dir)
		return raw, err

	case "loadExtensionFromPath":
		filePath, err := a.requiredString("file_path")
		if err != nil {
			return nil, err
		}
		raw, err := gobackend.LoadExtensionFromPath(filePath)
		return raw, err

	case "unloadExtension":
		extensionID, err := a.requiredString("extension_id")
		if err != nil {
			return nil, err
		}
		return nil, gobackend.UnloadExtensionByID(extensionID)

	case "removeExtension":
		extensionID, err := a.requiredString("extension_id")
		if err != nil {
			return nil, err
		}
		return nil, gobackend.RemoveExtensionByID(extensionID)

	case "getInstalledExtensions":
		raw, err := gobackend.GetInstalledExtensions()
		return raw, err

	case "setExtensionEnabled":
		extensionID, err := a.requiredString("extension_id")
		if err != nil {
			return nil, err
		}
		enabled, err := a.requiredBool("enabled")
		if err != nil {
			return nil, err
		}
		return nil, gobackend.SetExtensionEnabledByID(extensionID, enabled)

	case "getExtensionPendingAuth":
		extensionID, err := a.requiredString("extension_id")
		if err != nil {
			return nil, err
		}
		raw, err := gobackend.GetExtensionPendingAuthJSON(extensionID)
		return raw, err

	case "setExtensionSessionGrantByID":
		extensionID, err := a.requiredString("extension_id")
		if err != nil {
			return nil, err
		}
		grant, err := a.requiredString("grant")
		if err != nil {
			return nil, err
		}
		gobackend.SetExtensionSessionGrantByID(extensionID, grant)
		return nil, nil

	case "invokeExtensionAction":
		extensionID, err := a.requiredString("extension_id")
		if err != nil {
			return nil, err
		}
		action, err := a.requiredString("action")
		if err != nil {
			return nil, err
		}
		raw, err := gobackend.InvokeExtensionActionJSON(extensionID, action)
		return raw, err

	case "setProviderPriority":
		priority, err := a.jsonText("priority")
		if err != nil {
			return nil, err
		}
		return nil, gobackend.SetProviderPriorityJSON(priority)

	case "getProviderPriority":
		raw, err := gobackend.GetProviderPriorityJSON()
		return raw, err

	case "setMetadataProviderPriority":
		priority, err := a.jsonText("priority")
		if err != nil {
			return nil, err
		}
		return nil, gobackend.SetMetadataProviderPriorityJSON(priority)

	case "getMetadataProviderPriority":
		raw, err := gobackend.GetMetadataProviderPriorityJSON()
		return raw, err

	case "setFallbackProviders":
		providerIDs, err := a.jsonText("provider_ids")
		if err != nil {
			return nil, err
		}
		return nil, gobackend.SetExtensionFallbackProviderIDsJSON(providerIDs)

	// ─── Extension repository ───────────────────────────────────────────
	case "setRepoRegistryUrl":
		registryURL, err := a.requiredString("registry_url")
		if err != nil {
			return nil, err
		}
		return nil, gobackend.SetRepoRegistryURLJSON(registryURL)

	case "getRepoRegistryUrl":
		raw, err := gobackend.GetRepoRegistryURLJSON()
		return raw, err

	case "clearRepoRegistryUrl":
		return nil, gobackend.ClearRepoRegistryURLJSON()

	case "getRepoExtensions":
		forceRefresh, err := a.requiredBool("force_refresh")
		if err != nil {
			return nil, err
		}
		raw, err := gobackend.GetRepoExtensionsJSON(forceRefresh)
		return raw, err

	case "getRepoCategories":
		raw, err := gobackend.GetRepoCategoriesJSON()
		return raw, err

	case "downloadRepoExtension":
		extensionID, err := a.requiredString("extension_id")
		if err != nil {
			return nil, err
		}
		destDir, err := a.requiredString("dest_dir")
		if err != nil {
			return nil, err
		}
		raw, err := gobackend.DownloadRepoExtensionJSON(extensionID, destDir)
		return raw, err

	// ─── Downloads ──────────────────────────────────────────────────────
	case "downloadByStrategy":
		requestJSON, err := a.requiredString("request_json")
		if err != nil {
			return nil, err
		}
		raw, err := gobackend.DownloadByStrategy(requestJSON)
		return raw, err

	case "getAllDownloadProgress":
		return gobackend.GetAllDownloadProgress(), nil

	case "getAllDownloadProgressDelta":
		sinceSeq, err := a.int64Value("since_seq")
		if err != nil {
			return nil, err
		}
		return gobackend.GetAllDownloadProgressDelta(sinceSeq), nil

	case "initItemProgress":
		itemID, err := a.requiredString("item_id")
		if err != nil {
			return nil, err
		}
		gobackend.InitItemProgress(itemID)
		return nil, nil

	case "clearItemProgress":
		itemID, err := a.requiredString("item_id")
		if err != nil {
			return nil, err
		}
		gobackend.ClearItemProgress(itemID)
		return nil, nil

	case "cancelDownload":
		itemID, err := a.requiredString("item_id")
		if err != nil {
			return nil, err
		}
		gobackend.CancelDownload(itemID)
		return nil, nil

	case "resetDownloadCancel":
		itemID, err := a.requiredString("item_id")
		if err != nil {
			return nil, err
		}
		gobackend.ResetDownloadCancel(itemID)
		return nil, nil

	case "runPostProcessingV2":
		input, err := a.requiredString("input")
		if err != nil {
			return nil, err
		}
		metadata, err := a.optionalString("metadata")
		if err != nil {
			return nil, err
		}
		raw, err := gobackend.RunPostProcessingV2JSON(input, metadata)
		return raw, err

	// ─── Files / metadata ───────────────────────────────────────────────
	case "editFileMetadata":
		filePath, err := a.requiredString("file_path")
		if err != nil {
			return nil, err
		}
		metadataJSON, err := a.requiredString("metadata_json")
		if err != nil {
			return nil, err
		}
		raw, err := gobackend.EditFileMetadata(filePath, metadataJSON)
		return raw, err

	case "readFileMetadata":
		filePath, err := a.requiredString("file_path")
		if err != nil {
			return nil, err
		}
		raw, err := gobackend.ReadFileMetadata(filePath)
		return raw, err

	case "downloadCoverToFile":
		// The Go export returns only an error; on success the call resolves
		// to null (the Dart side treats that as ok).
		coverURL, err := a.requiredString("cover_url")
		if err != nil {
			return nil, err
		}
		outputPath, err := a.requiredString("output_path")
		if err != nil {
			return nil, err
		}
		maxQuality, err := a.requiredBool("max_quality")
		if err != nil {
			return nil, err
		}
		return nil, gobackend.DownloadCoverToFile(coverURL, outputPath, maxQuality)

	case "getDeezerExtendedMetadata":
		trackID, err := a.requiredString("track_id")
		if err != nil {
			return nil, err
		}
		raw, err := gobackend.GetDeezerExtendedMetadata(trackID)
		return raw, err

	// ─── Library scan (Linux-only; the Android build uses MediaStore) ───
	case "setLibraryCoverCacheDirJSON":
		cacheDir, err := a.requiredString("cache_dir")
		if err != nil {
			return nil, err
		}
		gobackend.SetLibraryCoverCacheDirJSON(cacheDir)
		return nil, nil

	case "scanLibraryFolderIncrementalJSON":
		folderPath, err := a.requiredString("folder_path")
		if err != nil {
			return nil, err
		}
		existingFilesJSON, err := a.optionalString("existing_files_json")
		if err != nil {
			return nil, err
		}
		raw, err := gobackend.ScanLibraryFolderIncrementalJSON(folderPath, existingFilesJSON)
		return raw, err

	// ─── Lyrics ─────────────────────────────────────────────────────────
	case "getLyricsLRC":
		spotifyID, err := a.optionalString("spotify_id")
		if err != nil {
			return nil, err
		}
		trackName, err := a.optionalString("track_name")
		if err != nil {
			return nil, err
		}
		artistName, err := a.optionalString("artist_name")
		if err != nil {
			return nil, err
		}
		filePath, err := a.optionalString("file_path")
		if err != nil {
			return nil, err
		}
		durationMs, err := a.int64Value("duration_ms")
		if err != nil {
			return nil, err
		}
		raw, err := gobackend.GetLyricsLRC(spotifyID, trackName, artistName, filePath, durationMs)
		return raw, err

	// ─── Diagnostics / housekeeping ─────────────────────────────────────
	case "releaseMemory":
		gobackend.ReleaseMemory()
		return nil, nil

	case "releaseMemoryUnderPressure":
		gobackend.ReleaseMemoryUnderPressure()
		return nil, nil

	case "cleanupConnections":
		gobackend.CleanupConnections()
		return nil, nil

	case "cleanupExtensions":
		gobackend.CleanupExtensions()
		return nil, nil

	case "getGoLogsSince":
		index, err := a.int64Value("index")
		if err != nil {
			return nil, err
		}
		return gobackend.GetLogsSince(int(index)), nil

	case "getGoRuntimeMetrics":
		return gobackend.GetRuntimeMetricsJSON(), nil

	default:
		return nil, fmt.Errorf("unhandled bridge method: %s", method)
	}
}

func handle(req request) {
	var a args
	if len(req.Args) > 0 {
		if err := json.Unmarshal(req.Args, &a); err != nil {
			writeLine(errorResponse{ID: req.ID, Error: errorInfo{
				Code:    "go_backend_error",
				Message: fmt.Sprintf("invalid args: %v", err),
			}})
			return
		}
	}

	defer func() {
		if recovered := recover(); recovered != nil {
			log.Printf("panic in %s: %v\n%s", req.Method, recovered, debug.Stack())
			writeLine(errorResponse{ID: req.ID, Error: errorInfo{
				Code:    "go_backend_error",
				Message: fmt.Sprintf("panic: %v", recovered),
			}})
		}
	}()

	result, err := dispatch(req.Method, a)
	if err != nil {
		writeLine(errorResponse{ID: req.ID, Error: errorInfo{
			Code:    "go_backend_error",
			Message: err.Error(),
		}})
		return
	}
	writeLine(response{ID: req.ID, Result: result})
}

func main() {
	// Keep stdout clean: it is the JSON-RPC pipe. Parts of the backend still
	// log with fmt.Printf (stdout), so redirect the process-wide stdout to a
	// pipe forwarded to stderr and keep the original handle for responses.
	r, w, err := os.Pipe()
	if err == nil {
		os.Stdout = w
		go func() { _, _ = io.Copy(os.Stderr, r) }()
	}

	log.SetOutput(os.Stderr)
	log.SetFlags(log.Ltime | log.Lmicroseconds)

	gobackend.SetAppVersion(appVersion)

	reader := bufio.NewReaderSize(os.Stdin, 1<<20)
	for {
		line, err := reader.ReadString('\n')
		line = strings.TrimSpace(line)
		if line != "" {
			var req request
			if decodeErr := json.Unmarshal([]byte(line), &req); decodeErr != nil {
				log.Printf("invalid request line: %v", decodeErr)
			} else {
				// Downloads and processing hooks block for minutes; run every
				// request on its own goroutine so progress polls, cancels and
				// library scans stay responsive.
				handlersWG.Add(1)
				go func(req request) {
					defer handlersWG.Done()
					handle(req)
				}(req)
			}
		}
		if err != nil {
			if err != io.EOF {
				log.Printf("stdin read error: %v", err)
			}
			break
		}
	}

	// The host closed the pipe; let in-flight requests report their result
	// before exiting.
	handlersWG.Wait()
}
