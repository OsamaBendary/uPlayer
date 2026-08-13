import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:u_player/core/services/go/go_backend_bridge.dart';

enum DownloadQuality {
  flac24('FLAC 24-bit', 'Lossless Hi-Res (24-bit/96kHz)'),
  flac16('FLAC 16-bit', 'Lossless CD Quality (16-bit/44.1kHz)'),
  mp3320('MP3 320k', 'High Quality MP3 (320 kbps)'),
  mp3128('MP3 128k', 'Standard MP3 (128 kbps)');

  final String label;
  final String description;
  const DownloadQuality(this.label, this.description);
}

/// One selectable download quality: either one of the app's standard
/// qualities or a provider-specific quality option (e.g. "Dolby Atmos").
class DownloadQualityChoice {
  final DownloadQuality? appQuality;

  /// Provider quality option id, e.g. "DOLBY_ATMOS", "HI_RES_LOSSLESS".
  final String? providerQualityId;
  final String? label;
  final String? description;

  const DownloadQualityChoice({
    this.appQuality,
    this.providerQualityId,
    this.label,
    this.description,
  });

  factory DownloadQualityChoice.app(DownloadQuality quality) =>
      DownloadQualityChoice(
        appQuality: quality,
        label: quality.label,
        description: quality.description,
      );

  /// Rebuilds the choice a queued task was started with (for retries).
  factory DownloadQualityChoice.fromTask(
    DownloadQuality quality,
    String? providerQualityId,
  ) {
    final token = providerQualityId?.trim();
    if (token != null && token.isNotEmpty) {
      return DownloadQualityChoice(providerQualityId: token, label: token);
    }
    return DownloadQualityChoice.app(quality);
  }

  bool matches(DownloadQualityChoice other) {
    if (providerQualityId != null || other.providerQualityId != null) {
      return providerQualityId != null &&
          other.providerQualityId != null &&
          providerQualityId!.toLowerCase() ==
              other.providerQualityId!.toLowerCase();
    }
    return appQuality == other.appQuality;
  }
}

/// Official community registry so the store works out of the box,
/// mirroring SpotiFLaC's own default store.
const String kOfficialExtensionRepo = 'https://github.com/zarzet/SpotiFLAC-Extension';

class ExtensionManifest {
  final String id;
  final String name;
  final String version;
  final String description;
  final String type;
  final String? baseUrl;
  final String? downloadUrl;
  final String? sha256;
  final String? category;
  final String? homepage;
  final bool hasDownloadProvider;
  bool isEnabled;

  /// Raw JSON from the Go backend (`getInstalledExtensions`) so pipeline
  /// helpers can read capability fields the manifest model does not parse:
  /// `post_processing`, `capabilities`, `quality_options`, ...
  final Map<String, dynamic> raw;

  ExtensionManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.type,
    this.baseUrl,
    this.downloadUrl,
    this.sha256,
    this.category,
    this.homepage,
    this.hasDownloadProvider = false,
    this.isEnabled = true,
    this.raw = const {},
  });

  /// True when this extension ships enabled post-processing hooks (ffmpeg
  /// conversion to FLAC after the provider stream lands). Matches the
  /// reference `postProcessing?.enabled`.
  bool get hasPostProcessing {
    final pp = raw['post_processing'];
    return pp is Map && pp['enabled'] == true;
  }

  /// The provider stream must not get lyrics embedded (raw DASH streams that
  /// would break on tag writes). Mirrors the reference `skip_lyrics`.
  bool get skipLyrics => raw['skip_lyrics'] == true;

  /// The extension converts non-FLAC provider streams (DASH/Opus/M4A) to
  /// lossless itself; the host must only request the output container.
  bool get requiresNativeContainerConversion {
    final caps = raw['capabilities'];
    if (caps is! Map) return false;
    return caps['requiresContainerConversion'] == true ||
        caps['requiresNativeContainerConversion'] == true;
  }

  /// Built-in provider ids this extension replaces (["tidal"], ["deezer"], ...).
  List<String> get replacesBuiltInProviders {
    final caps = raw['capabilities'];
    if (caps is! Map) return const [];
    final value = caps['replacesBuiltInProviders'];
    if (value is! List) return const [];

    final normalized = <String>[];
    for (final item in value) {
      if (item is! String) continue;
      final trimmed = item.trim().toLowerCase();
      if (trimmed.isEmpty || normalized.contains(trimmed)) continue;
      normalized.add(trimmed);
    }
    return normalized;
  }

  /// Preferred output extension advertised by the extension (e.g. ".flac"),
  /// or null when the extension does not impose one.
  String? get preferredDownloadOutputExtension {
    final caps = raw['capabilities'];
    if (caps is! Map) return null;
    final value = caps['downloadOutputExtension'];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Native output extensions that must be kept as-is (e.g. ".m4a" for
  /// Dolby/DASH decrypted streams that cannot be upscaled to FLAC).
  List<String> get preservedNativeOutputExtensions {
    final caps = raw['capabilities'];
    if (caps is! Map) return const [];
    final value = caps['preserveNativeOutputExtensions'];
    if (value is! List) return const [];

    final normalized = <String>[];
    for (final item in value) {
      if (item is! String) continue;
      final trimmed = item.trim().toLowerCase();
      if (trimmed.isEmpty) continue;
      normalized.add(trimmed.startsWith('.') ? trimmed : '.$trimmed');
    }
    return normalized;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'description': description,
        'type': type,
        'baseUrl': baseUrl,
        'downloadUrl': downloadUrl,
        'sha256': sha256,
        'category': category,
        'homepage': homepage,
        'hasDownloadProvider': hasDownloadProvider,
        'isEnabled': isEnabled,
      };

  factory ExtensionManifest.fromJson(Map<String, dynamic> json) {
    String parsedType = 'download';
    if (json['type'] != null) {
      parsedType = (json['type'] is List)
          ? (json['type'] as List).first.toString()
          : json['type'].toString();
    } else if (json['category'] != null) {
      parsedType = json['category'].toString();
    }

    return ExtensionManifest(
      id: json['id'] as String? ??
          json['name'] as String? ??
          'ext_${DateTime.now().millisecondsSinceEpoch}',
      name: json['display_name'] as String? ??
          json['displayName'] as String? ??
          json['name'] as String? ??
          'Extension',
      version: json['version'] as String? ?? '1.0.0',
      description: json['description'] as String? ?? '',
      type: parsedType,
      baseUrl: json['baseUrl'] as String? ?? json['homepage'] as String?,
      downloadUrl: json['download_url'] as String? ??
          json['downloadUrl'] as String?,
      sha256: json['sha256'] as String?,
      category: json['category'] as String?,
      homepage: json['homepage'] as String?,
      hasDownloadProvider:
          json['has_download_provider'] == true || json['category'] == 'download',
      isEnabled: json['isEnabled'] as bool? ?? true,
      raw: json,
    );
  }

  /// Parses one entry from the Go extension store (`getRepoExtensions`).
  factory ExtensionManifest.fromGoRepo(Map<String, dynamic> json) {
    return ExtensionManifest(
      id: (json['id'] ?? '').toString(),
      name: (json['display_name'] ?? json['name'] ?? '').toString(),
      version: (json['version'] ?? '1.0.0').toString(),
      description: (json['description'] ?? '').toString(),
      type: (json['category'] ?? 'download').toString(),
      baseUrl: json['homepage']?.toString(),
      downloadUrl: (json['download_url'] ?? '').toString(),
      sha256: json['sha256']?.toString(),
      category: json['category']?.toString(),
      hasDownloadProvider: (json['category'] ?? '').toString() == 'download',
      isEnabled: true,
    );
  }

  /// Parses one installed extension from `getInstalledExtensions`.
  factory ExtensionManifest.fromInstalledGo(Map<String, dynamic> json) {
    final types = json['types'];
    String parsedType = 'unknown';
    if (types is List && types.isNotEmpty) {
      parsedType = types.first.toString();
    }
    return ExtensionManifest(
      id: (json['id'] ?? '').toString(),
      name: (json['display_name'] ?? json['name'] ?? '').toString(),
      version: (json['version'] ?? '1.0.0').toString(),
      description: (json['description'] ?? '').toString(),
      type: parsedType,
      baseUrl: json['homepage']?.toString(),
      hasDownloadProvider: json['has_download_provider'] == true,
      isEnabled: json['enabled'] == true,
      raw: json,
    );
  }
}

class SearchResultTrack {
  final String id;
  final String name;
  final String artist;
  final String album;
  final int durationMs;
  final String? coverUrl;

  /// Direct download URL — null for Deezer results where the URL must be
  /// resolved at download time via JioSaavn (avoids 30-sec preview links).
  final String? downloadUrl;

  /// Deezer numeric track ID.  Used by DownloadService to attempt a more
  /// targeted full-track search when resolving via Saavn fails.
  final String? deezerTrackId;

  /// 1-based track number within the album (from Deezer track_position).
  final int? trackNumber;

  /// Release year extracted from Deezer release_date (e.g. "2019-05-17" → "2019").
  final String? releaseYear;

  final String providerName;

  /// Highest available quality label (e.g. "FLAC 16-bit", "320 kbps").
  final String qualityLabel;

  SearchResultTrack({
    required this.id,
    required this.name,
    required this.artist,
    required this.album,
    required this.durationMs,
    this.coverUrl,
    this.downloadUrl,
    this.deezerTrackId,
    this.trackNumber,
    this.releaseYear,
    required this.providerName,
    this.qualityLabel = 'FLAC 16-bit',
  });
}

class SearchResultAlbum {
  final String id;
  final String name;
  final String artist;
  final String? coverUrl;
  final int trackCount;
  final String recordType;
  final String releaseDate;

  SearchResultAlbum({
    required this.id,
    required this.name,
    required this.artist,
    this.coverUrl,
    this.trackCount = 0,
    this.recordType = 'album',
    this.releaseDate = '',
  });
}

class SearchResultArtist {
  final String id;
  final String name;
  final String? coverUrl;

  SearchResultArtist({
    required this.id,
    required this.name,
    this.coverUrl,
  });
}

class ExtensionService {
  static final ExtensionService _instance = ExtensionService._internal();
  factory ExtensionService() => _instance;
  ExtensionService._internal();

  static const String _prefRepoUrlsKey = 'user_extension_repo_urls';
  static const String _prefExtensionsKey = 'user_installed_extensions';
  static const String _prefQualityKey = 'selected_download_quality';
  static const String _prefProviderIdKey = 'selected_download_provider';
  static const String _prefStoreCacheKey = 'extension_store_cache';

  static const Map<String, String> _englishHeaders = {
    'Accept-Language': 'en-US,en;q=0.9',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  };

  /// Known providers that require an account session / one-time verification
  /// before they serve audio. Others (SoundCloud, YouTube Music, ...) work
  /// with zero login.
  static const Set<String> _loginRequiredProviderIds = {
    'tidal-web',
    'tidal',
    'qobuz-web',
    'qobuz',
    'deezer',
    'amazon',
    'amzn',
    'pandora',
  };

  /// Providers that can actually deliver FLAC/lossless streams. The rest
  /// (SoundCloud, YouTube Music, ...) top out at Opus/MP3, so when the user
  /// picks a lossless quality these must be tried first.
  static const Set<String> _losslessCapableProviderIds = {
    'tidal-web',
    'tidal',
    'qobuz-web',
    'qobuz',
    'deezer',
    'amazon',
    'amzn',
    'apple',
    'apple-music',
    'pandora',
  };

  static bool requiresLogin(String providerId) =>
      _loginRequiredProviderIds.contains(providerId.toLowerCase());

  static bool canDeliverLossless(String providerId) =>
      _losslessCapableProviderIds.contains(providerId.toLowerCase());

  List<String> repoUrls = [];
  List<ExtensionManifest> installedExtensions = [];
  List<ExtensionManifest> availableRepoExtensions = [];
  DownloadQuality selectedQuality = DownloadQuality.flac16;

  /// Download provider id the user explicitly picked ("tidal", "qobuz", ...).
  /// Null means auto — Go iterates the provider priority list.
  String? selectedProviderId;

  bool _initializing = false;

  /// Last-known store contents persisted across launches (offline-safe).
  List<ExtensionManifest> _storeCache = [];

  /// Loads prefs (repos, quality, cached installed list), syncs the active
  /// repo into the Go backend, reloads real installed extensions from Go and
  /// pushes the download provider priority so downloads can actually run.
  /// Fast on first launch: no blocking network calls.
  Future<void> init() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      repoUrls = prefs.getStringList(_prefRepoUrlsKey) ?? [];
      final extRaw = prefs.getStringList(_prefExtensionsKey) ?? [];
      final cached =
          extRaw.map((e) => ExtensionManifest.fromJson(jsonDecode(e))).toList();

      final qualityIdx = prefs.getInt(_prefQualityKey) ?? 1;
      selectedQuality =
          DownloadQuality.values[qualityIdx.clamp(0, DownloadQuality.values.length - 1)];
      selectedProviderId = prefs.getString(_prefProviderIdKey);
      installedExtensions = cached.isNotEmpty ? cached : _cachedPlaceholderList();
      await _loadStoreCache();

      final bridge = GoBackendBridge.instance;
      if (bridge.isAvailable) {
        try {
          await _syncActiveRepoToGo();
          await _refreshInstalledFromGo();
          await _reconcileProviderPriority();
        } catch (e) {
          debugPrint('[ExtensionService] Go sync failed: $e');
        }
      }
    } finally {
      _initializing = false;
    }
  }

  List<ExtensionManifest> _cachedPlaceholderList() => [];

  Future<void> setQuality(DownloadQuality quality) async {
    selectedQuality = quality;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefQualityKey, quality.index);
    await _reconcileProviderPriority();
  }

  /// Enabled download providers (what the chip row under the search bar shows).
  /// Ordered like the Go priority: lossless-capable first when the selected
  /// quality is lossless, otherwise login-free first.
  List<ExtensionManifest> get downloadProviders {
    final losslessQuality = selectedQuality == DownloadQuality.flac24 ||
        selectedQuality == DownloadQuality.flac16;
    final providers =
        installedExtensions.where((e) => e.isEnabled && e.hasDownloadProvider).toList()
          ..sort((a, b) {
            if (losslessQuality) {
              final aLossless = canDeliverLossless(a.id);
              final bLossless = canDeliverLossless(b.id);
              if (aLossless != bLossless) return aLossless ? -1 : 1;
            }
            final aLogin = requiresLogin(a.id);
            final bLogin = requiresLogin(b.id);
            if (aLogin != bLogin) return aLogin ? 1 : -1;
            return a.id.compareTo(b.id);
          });
    return providers;
  }

  /// Picks the provider downloads should prefer. Null = auto (Go priority).
  Future<void> setDownloadProvider(String? providerId) async {
    selectedProviderId =
        (providerId == null || providerId.isEmpty) ? null : providerId;
    final prefs = await SharedPreferences.getInstance();
    if (selectedProviderId == null) {
      await prefs.remove(_prefProviderIdKey);
    } else {
      await prefs.setString(_prefProviderIdKey, selectedProviderId!);
    }
  }

  /// True when any enabled download extension ships enabled post-processing
  /// hooks (the host must invoke them after the download lands).
  bool hasEnabledPostProcessing() =>
      installedExtensions.any((e) => e.isEnabled && e.hasPostProcessing);

  /// True when [source]/[service] matches an enabled extension that asks the
  /// host to skip lyrics (raw DASH streams that break on tag writes).
  bool skipLyricsFor(String? source, String? service) {
    final candidates = <String>{};
    if (source != null && source.isNotEmpty) {
      candidates.add(source.trim().toLowerCase());
    }
    if (service != null && service.isNotEmpty) {
      candidates.add(service.trim().toLowerCase());
    }
    if (candidates.isEmpty) return false;
    return installedExtensions.any((e) =>
        e.isEnabled &&
        e.skipLyrics &&
        candidates.contains(e.id.toLowerCase()));
  }

  /// True when the enabled extension responsible for [service] converts
  /// non-FLAC provider streams to lossless itself; the client must only ask
  /// for the right output container.
  bool requiresNativeContainerConversionFor(String service) {
    final normalizedService = service.trim().toLowerCase();
    if (normalizedService.isEmpty) return false;
    return installedExtensions.any((e) =>
        e.isEnabled &&
        e.hasDownloadProvider &&
        e.id.toLowerCase() == normalizedService &&
        e.requiresNativeContainerConversion);
  }

  /// Preferred output extension advertised by the extension serving
  /// [service] (e.g. ".flac"), or null when it imposes none. `.mp4` is
  /// normalized to `.m4a`.
  String? preferredDownloadOutputExtensionFor(String service) {
    final normalizedService = service.trim().toLowerCase();
    if (normalizedService.isEmpty) return null;
    for (final ext in installedExtensions) {
      if (!ext.isEnabled || !ext.hasDownloadProvider) continue;
      if (ext.id.toLowerCase() != normalizedService) continue;
      final preferred = ext.preferredDownloadOutputExtension;
      if (preferred == null) return null;
      final normalized = preferred.startsWith('.')
          ? preferred.toLowerCase()
          : '.${preferred.toLowerCase()}';
      if (normalized == '.mp4') return '.m4a';
      const allowed = <String>{'.flac', '.m4a', '.mp3', '.opus'};
      if (allowed.contains(normalized)) return normalized;
      return null;
    }
    return null;
  }

  /// True when the enabled extension serving [service] must keep the native
  /// output extension (e.g. ".m4a" for Dolby/DASH streams).
  bool preservesNativeOutputExtension(String service, String ext) {
    final normalizedService = service.trim().toLowerCase();
    final normalizedExt = ext.trim().toLowerCase();
    if (normalizedService.isEmpty || normalizedExt.isEmpty) return false;
    return installedExtensions.any((e) =>
        e.isEnabled &&
        e.hasDownloadProvider &&
        e.id.toLowerCase() == normalizedService &&
        e.preservedNativeOutputExtensions.contains(normalizedExt));
  }

  /// True when the enabled extension serving [service] replaces the built-in
  /// provider [legacyProviderId] (e.g. "tidal").
  bool replacesBuiltInProvider(String service, String legacyProviderId) {
    final normalizedService = service.trim().toLowerCase();
    final normalizedLegacy = legacyProviderId.trim().toLowerCase();
    if (normalizedService.isEmpty || normalizedLegacy.isEmpty) return false;
    return installedExtensions.any((e) =>
        e.isEnabled &&
        e.hasDownloadProvider &&
        e.id.toLowerCase() == normalizedService &&
        e.replacesBuiltInProviders.contains(normalizedLegacy));
  }

  /// Best provider to pin lossless downloads to when the user hasn't picked
  /// one explicitly: Tidal, then Qobuz, then the first enabled lossless-
  /// capable installed extension. Matches both legacy ("tidal") and current
  /// registry ("tidal-web") ids. Null when nothing usable is installed.
  String? losslessPreferredProvider() {
    final installed = installedExtensions
        .where((e) => e.isEnabled && e.hasDownloadProvider)
        .toList();
    for (final preferred in const ['tidal', 'tidal-web']) {
      if (installed.any((e) => e.id.toLowerCase() == preferred)) return preferred;
    }
    for (final preferred in const ['qobuz', 'qobuz-web']) {
      if (installed.any((e) => e.id.toLowerCase() == preferred)) return preferred;
    }
    for (final ext in installed) {
      if (canDeliverLossless(ext.id)) return ext.id;
    }
    return null;
  }

  /// Highest audio quality the enabled download providers advertise, shown
  /// on search results. Stable — independent of the user's selected download
  /// quality — so the badge reflects what providers can actually deliver
  /// instead of changing whenever the quality setting changes.
  String highestAvailableQualityLabel() {
    String? bestLabel;
    var bestRank = 99;
    for (final ext in installedExtensions) {
      if (!ext.isEnabled || !ext.hasDownloadProvider) continue;
      final rawOptions = ext.raw['quality_options'];
      if (rawOptions is! List) continue;
      for (final option in rawOptions) {
        if (option is! Map) continue;
        final id = option['id']?.toString().trim().toLowerCase() ?? '';
        if (id.isEmpty) continue;
        final label = option['label']?.toString().trim() ?? '';
        final rank = _qualityOptionRank(id);
        if (rank >= bestRank) continue;
        bestRank = rank;
        bestLabel = _qualityOptionLabel(rank, label);
      }
    }
    if (bestLabel != null) return bestLabel;
    final hasLossless = installedExtensions.any(
        (e) => e.isEnabled && e.hasDownloadProvider && canDeliverLossless(e.id));
    return hasLossless ? 'FLAC 16-bit' : 'MP3 320k';
  }

  static int _qualityOptionRank(String id) {
    if (id.contains('dolby')) return 0;
    if (id.contains('hi_res') ||
        id.contains('hires') ||
        (id.contains('flac') && id.contains('24'))) {
      return 1;
    }
    if (id.contains('flac') ||
        id.contains('lossless') ||
        id.contains('alac') ||
        id.contains('master')) {
      return 2;
    }
    if (id.contains('320') ||
        id.contains('high') ||
        id.contains('mp3') ||
        id.contains('opus') ||
        id.contains('aac')) {
      return 3;
    }
    if (id.contains('128') || id.contains('low')) return 4;
    return 5;
  }

  static String _qualityOptionLabel(int rank, String label) => switch (rank) {
        0 => label.isNotEmpty ? label : 'Dolby Atmos',
        1 => label.isNotEmpty ? label : 'FLAC 24-bit',
        2 => 'FLAC 16-bit',
        3 => 'MP3 320k',
        _ => 'MP3 128k',
      };

  /// Adds a repository URL, syncs it into the Go backend, then refreshes the
  /// store from Go (the registry URL is resolved + cached there).
  Future<void> addRepoUrl(String url) async {
    if (!repoUrls.contains(url)) {
      repoUrls.add(url);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefRepoUrlsKey, repoUrls);
    }
    await _syncActiveRepoToGo();
    await refreshStore();
  }

  Future<void> removeRepoUrl(String url) async {
    repoUrls.remove(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefRepoUrlsKey, repoUrls);

    final bridge = GoBackendBridge.instance;
    if (bridge.isAvailable) {
      if (repoUrls.isEmpty) {
        try {
          await bridge.clearRepoRegistryUrl();
        } catch (_) {}
      } else {
        try {
          await bridge.setRepoRegistryUrl(repoUrls.last);
        } catch (_) {}
      }
    }
    await refreshStore();
  }

  /// Pushes the active (last added) repo URL into the Go extension store.
  Future<void> _syncActiveRepoToGo() async {
    final bridge = GoBackendBridge.instance;
    if (!bridge.isAvailable) return;
    if (repoUrls.isEmpty) {
      try {
        await bridge.clearRepoRegistryUrl();
      } catch (_) {}
    } else {
      try {
        await bridge.setRepoRegistryUrl(repoUrls.last);
      } catch (e) {
        debugPrint('[ExtensionService] setRepoRegistryUrl failed: $e');
      }
    }
  }

  /// Refreshes the store list. Falls back through: Go force-refresh → Go
  /// cached registry → last-known persisted store → plain HTTP. Only returns
  /// an empty list when every path fails.
  Future<List<ExtensionManifest>> refreshStore() async {
    final bridge = GoBackendBridge.instance;

    if (bridge.isAvailable) {
      try {
        final raw = await bridge.getRepoExtensions(forceRefresh: true);
        availableRepoExtensions =
            raw.map(ExtensionManifest.fromGoRepo).toList();
        await _saveStoreCache();
        return availableRepoExtensions;
      } catch (e) {
        debugPrint('[ExtensionService] Go store force-refresh failed: $e');
      }
      try {
        final raw = await bridge.getRepoExtensions(forceRefresh: false);
        availableRepoExtensions =
            raw.map(ExtensionManifest.fromGoRepo).toList();
        await _saveStoreCache();
        return availableRepoExtensions;
      } catch (e) {
        debugPrint('[ExtensionService] Go store cache fetch failed: $e');
      }
    }

    if (_storeCache.isNotEmpty) {
      availableRepoExtensions = List.of(_storeCache);
      return availableRepoExtensions;
    }

    final List<ExtensionManifest> fetched = [];
    for (final repo in repoUrls) {
      fetched.addAll(await fetchExtensionsFromRepo(repo));
    }
    if (fetched.isNotEmpty) {
      availableRepoExtensions = fetched;
      await _saveStoreCache();
      return fetched;
    }

    if (_storeCache.isNotEmpty) {
      availableRepoExtensions = List.of(_storeCache);
      return availableRepoExtensions;
    }
    availableRepoExtensions = [];
    return [];
  }

  /// Loads the persisted store snapshot (last successful Go fetch).
  Future<void> _loadStoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefStoreCacheKey) ?? [];
      _storeCache =
          raw.map((e) => ExtensionManifest.fromGoRepo(jsonDecode(e) as Map<String, dynamic>)).toList();
    } catch (e) {
      _storeCache = [];
    }
  }

  Future<void> _saveStoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _storeCache = List.of(availableRepoExtensions);
      await prefs.setStringList(
        _prefStoreCacheKey,
        _storeCache.map((e) => jsonEncode(e.toJson())).toList(),
      );
    } catch (e) {
      debugPrint('[ExtensionService] store cache save failed: $e');
    }
  }

Future<List<ExtensionManifest>> fetchExtensionsFromRepo(String repoUrl) async {
    final candidates = _rawRegistryCandidates(repoUrl);
    for (final uri in candidates) {
      try {
        final response = await http
            .get(Uri.parse(uri), headers: _englishHeaders)
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          List<dynamic> rawList = [];

          if (decoded is List) {
            rawList = decoded;
          } else if (decoded is Map<String, dynamic>) {
            rawList = (decoded['extensions'] ?? decoded['apps'] ?? decoded['data'] ?? [])
                as List<dynamic>;
          }

          final List<ExtensionManifest> fetched = [];
          for (final item in rawList) {
            if (item is Map<String, dynamic>) {
              fetched.add(ExtensionManifest.fromJson(item));
            }
          }
          if (fetched.isNotEmpty) return fetched;
        }
      } catch (e) {
        debugPrint('ExtensionService fetchExtensionsFromRepo error ($uri): $e');
      }
    }
    return [];
  }

  /// Raw JSON candidates for a repo URL: as-is, plus the GitHub
  /// raw.githubusercontent.com registry.json form (mirrors Go's resolver).
  static List<String> _rawRegistryCandidates(String repoUrl) {
    final url = repoUrl.trim();
    final candidates = <String>[url];
    const ghPrefix = 'https://github.com/';
    if (url.startsWith(ghPrefix)) {
      final path = url.substring(ghPrefix.length).split('/');
      if (path.length >= 2) {
        candidates.add(
          'https://raw.githubusercontent.com/${path[0]}/${path[1]}/main/registry.json',
        );
      }
    }
    return candidates;
  }

  /// Real extension install: downloads the `.spotiflac-ext`/`.sflx` package
  /// from the Go store, loads it into the Go extension system (persisted under
  /// the app's extensions dir), enables it, then reconciles provider priority.
  /// Returns null on success, else a human-readable error message.
  Future<String?> installExtension(ExtensionManifest manifest) async {
    final bridge = GoBackendBridge.instance;
    final dirs = bridge.appDirs;
    if (!bridge.isAvailable || dirs == null || manifest.id.isEmpty) {
      return 'Go backend unavailable';
    }
    try {
      final destDir = '${dirs['cache_dir'] ?? ''}/extension_packages';
      Directory(destDir).createSync(recursive: true);
      final packagePath = await bridge.downloadRepoExtension(manifest.id, destDir);
      if (packagePath.isEmpty) return 'Download failed — no package returned';
      await bridge.loadExtensionFromPath(packagePath);
      await bridge.setExtensionEnabled(manifest.id, true);
      await _refreshInstalledFromGo();
      await _reconcileProviderPriority();
      return null;
    } on GoBackendCallException catch (e) {
      final errMsg = e.message;
      if (errMsg.contains('requires app')) {
        return 'This extension needs a newer app version ($errMsg)';
      }
      return 'Install failed: $errMsg';
    } catch (e) {
      debugPrint('[ExtensionService] installExtension failed: $e');
      return 'Install failed: $e';
    }
  }

  Future<void> toggleExtension(String id, bool enabled) async {
    final bridge = GoBackendBridge.instance;
    if (bridge.isAvailable) {
      try {
        await bridge.setExtensionEnabled(id, enabled);
      } catch (e) {
        debugPrint('[ExtensionService] setExtensionEnabled failed: $e');
      }
    }
    await _refreshInstalledFromGo();
    await _reconcileProviderPriority();
  }

  /// Removes an extension from the Go backend and refreshes the list.
  /// Returns null on success, else an error message.
  Future<String?> deleteExtension(String id) async {
    final bridge = GoBackendBridge.instance;
    if (bridge.isAvailable) {
      try {
        await bridge.removeExtension(id);
      } catch (e) {
        debugPrint('[ExtensionService] removeExtension failed: $e');
        await _refreshInstalledFromGo();
        await _reconcileProviderPriority();
        return 'Delete failed: $e';
      }
    }
    await _refreshInstalledFromGo();
    await _reconcileProviderPriority();
    return null;
  }

  /// Refreshes [installedExtensions] from the Go backend (source of truth)
  /// and persists a cache to prefs so the UI still lists them when the
  /// bridge is unavailable (e.g. debug builds without the AAR).
  Future<void> _refreshInstalledFromGo() async {
    final bridge = GoBackendBridge.instance;
    if (!bridge.isAvailable) return;
    try {
      final raw = await bridge.getInstalledExtensions();
      installedExtensions =
          raw.where((e) => (e['id'] ?? '').toString().isNotEmpty).map(ExtensionManifest.fromInstalledGo).toList();
      await _saveExtensions();
    } catch (e) {
      debugPrint('[ExtensionService] refresh installed failed: $e');
    }
  }

  /// Pushes the list of enabled download providers into the Go backend so the
  /// download pipeline actually has providers to try (it iterates priority).
  /// Login-free providers come first: when a provider demands verification,
  /// Go pauses the fallback chain, so keeping no-login providers ahead means
  /// "Auto" mode downloads without ever hitting a login wall. When the user
  /// picks a lossless quality, lossless-capable providers are moved ahead of
  /// lossy-only ones (SoundCloud/YouTube Music top out at Opus) so FLAC
  /// requests actually return FLAC. An explicit [selectedProviderId] is
  /// honored by the download request and moved to the front by Go itself.
  Future<void> _reconcileProviderPriority() async {
    final bridge = GoBackendBridge.instance;
    if (!bridge.isAvailable) return;
    final losslessQuality = selectedQuality == DownloadQuality.flac24 ||
        selectedQuality == DownloadQuality.flac16;
    final providers = installedExtensions
        .where((e) => e.isEnabled && e.hasDownloadProvider)
        .toList()
      ..sort((a, b) {
        if (losslessQuality) {
          final aLossless = canDeliverLossless(a.id);
          final bLossless = canDeliverLossless(b.id);
          if (aLossless != bLossless) return aLossless ? -1 : 1;
        }
        final aLogin = requiresLogin(a.id);
        final bLogin = requiresLogin(b.id);
        if (aLogin != bLogin) return aLogin ? 1 : -1;
        return a.id.compareTo(b.id);
      });
    final ids = providers.map((e) => e.id).toList();
    try {
      await bridge.setProviderPriority(ids);
      debugPrint('[ExtensionService] Provider priority: $ids');
    } catch (e) {
      debugPrint('[ExtensionService] setProviderPriority failed: $e');
    }
  }

  Future<void> _saveExtensions() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = installedExtensions.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_prefExtensionsKey, rawList);
  }

  // ─── Search ───────────────────────────────────────────────────────────────

  Future<List<SearchResultTrack>> searchTracks(String query) async {
    final List<SearchResultTrack> results = [];
    final activeProviders = installedExtensions.where((e) => e.isEnabled).toList();
    final providerName = activeProviders.isNotEmpty ? activeProviders.first.name : 'FLAC Provider';

    // 1. Deezer API (primary) — has the most complete metadata.
    //    We intentionally do NOT set downloadUrl here — the preview field is
    //    only 30 seconds.  DownloadService will resolve the full-length stream
    //    via JioSaavn using artist + title at download time.
    try {
      final deezerUri = Uri.parse('https://api.deezer.com/search?q=${Uri.encodeComponent(query)}&limit=30');
      final res = await http.get(deezerUri, headers: _englishHeaders).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final items = (data['data'] ?? []) as List;

        for (final item in items) {
          // Deezer duration is in seconds — convert to ms
          final durationSec = (item['duration'] ?? 0) as int;
          results.add(SearchResultTrack(
            id: item['id'].toString(),
            name: item['title'] ?? 'Unknown',
            artist: item['artist']?['name'] ?? 'Unknown Artist',
            album: item['album']?['title'] ?? 'Single',
            durationMs: durationSec * 1000,
            coverUrl: item['album']?['cover_xl'] ?? item['album']?['cover_medium'],
            // downloadUrl intentionally null — resolved at download time via Saavn
            downloadUrl: null,
            deezerTrackId: item['id'].toString(),
            releaseYear: _extractYear(item['album']?['release_date']),
            providerName: providerName,
            qualityLabel: highestAvailableQualityLabel(),
          ));
        }
      }
    } catch (e) {
      debugPrint('Deezer Track search error: $e');
    }

    // 2. iTunes API fallback — used only when Deezer returns nothing.
    //    iTunes also only gives preview URLs, so downloadUrl stays null.
    if (results.isEmpty) {
      try {
        final itunesUri = Uri.parse(
            'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=song&limit=25&lang=en_us&country=US');
        final res = await http
            .get(itunesUri, headers: _englishHeaders)
            .timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final items = (data['results'] ?? []) as List;

          for (final item in items) {
            final artwork100 = item['artworkUrl100'] as String?;
            final hiResCover = artwork100?.replaceAll('100x100bb', '600x600bb');
            // iTunes trackTimeMillis is already in ms
            final durationMs = (item['trackTimeMillis'] ?? 180000) as int;
            results.add(SearchResultTrack(
              id: item['trackId'].toString(),
              name: item['trackName'] ?? 'Unknown Track',
              artist: item['artistName'] ?? 'Unknown Artist',
              album: item['collectionName'] ?? 'Single',
              durationMs: durationMs,
              coverUrl: hiResCover ?? artwork100,
              // No download URL — will be resolved via Saavn
              downloadUrl: null,
              deezerTrackId: null,
              providerName: providerName,
              qualityLabel: highestAvailableQualityLabel(),
            ));
          }
        }
      } catch (e) {
        debugPrint('iTunes Track search error: $e');
      }
    }

    return results;
  }

  Future<List<SearchResultAlbum>> searchAlbums(String query) async {
    final List<SearchResultAlbum> results = [];

    try {
      final deezerUri = Uri.parse('https://api.deezer.com/search/album?q=${Uri.encodeComponent(query)}&limit=25');
      final res = await http.get(deezerUri, headers: _englishHeaders).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final items = (data['data'] ?? []) as List;

        for (final item in items) {
          results.add(SearchResultAlbum(
            id: item['id'].toString(),
            name: item['title'] ?? 'Unknown Album',
            artist: item['artist']?['name'] ?? 'Unknown Artist',
            coverUrl: item['cover_xl'] ?? item['cover_medium'],
            trackCount: item['nb_tracks'] ?? 0,
            recordType: item['record_type'] ?? 'album',
          ));
        }
      }
    } catch (e) {
      debugPrint('Album search error: $e');
    }

    return results;
  }

  Future<List<SearchResultArtist>> searchArtists(String query) async {
    final List<SearchResultArtist> results = [];

    try {
      final deezerUri = Uri.parse('https://api.deezer.com/search/artist?q=${Uri.encodeComponent(query)}&limit=25');
      final res = await http.get(deezerUri, headers: _englishHeaders).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final items = (data['data'] ?? []) as List;

        for (final item in items) {
          results.add(SearchResultArtist(
            id: item['id'].toString(),
            name: item['name'] ?? 'Unknown Artist',
            coverUrl: item['picture_xl'] ?? item['picture_medium'],
          ));
        }
      }
    } catch (e) {
      debugPrint('Artist search error: $e');
    }

    return results;
  }

  Future<List<SearchResultAlbum>> getArtistReleases(String artistId) async {
    final List<SearchResultAlbum> releases = [];
    try {
      final uri = Uri.parse('https://api.deezer.com/artist/$artistId/albums?limit=50');
      final res = await http.get(uri, headers: _englishHeaders).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final items = (data['data'] ?? []) as List;

        for (final item in items) {
          releases.add(SearchResultAlbum(
            id: item['id'].toString(),
            name: item['title'] ?? 'Release',
            artist: item['artist']?['name'] ?? 'Artist',
            coverUrl: item['cover_xl'] ?? item['cover_medium'],
            trackCount: item['nb_tracks'] ?? 0,
            recordType: item['record_type'] ?? 'album',
            releaseDate: item['release_date'] ?? '',
          ));
        }
      }
    } catch (e) {
      debugPrint('getArtistReleases error: $e');
    }
    return releases;
  }

  Future<List<SearchResultTrack>> getAlbumTracks(String albumId,
      {String? albumCoverUrl}) async {
    final List<SearchResultTrack> tracks = [];
    try {
      final uri = Uri.parse('https://api.deezer.com/album/$albumId');
      final res = await http.get(uri, headers: _englishHeaders).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final albumTitle = data['title'] ?? 'Album';
        final artistName = data['artist']?['name'] ?? 'Unknown Artist';
        final cover = albumCoverUrl ?? data['cover_xl'] ?? data['cover_medium'];
        final releaseYear = _extractYear(data['release_date']);
        final items = (data['tracks']?['data'] ?? []) as List;

        for (final item in items) {
          // Deezer gives duration in seconds
          final durationSec = (item['duration'] ?? 0) as int;
          tracks.add(SearchResultTrack(
            id: item['id'].toString(),
            name: item['title'] ?? 'Unknown',
            artist: item['artist']?['name'] ?? artistName,
            album: albumTitle,
            durationMs: durationSec * 1000,
            coverUrl: cover,
            // No download URL — resolved via Saavn at download time
            downloadUrl: null,
            deezerTrackId: item['id'].toString(),
            trackNumber: item['track_position'] as int?,
            releaseYear: releaseYear,
            providerName: 'FLAC Provider',
            qualityLabel: highestAvailableQualityLabel(),
          ));
        }
      }
    } catch (e) {
      debugPrint('getAlbumTracks error: $e');
    }
    return tracks;
  }

  /// Extracts a 4-digit year from a Deezer date string like "2019-05-17".
  static String? _extractYear(dynamic dateStr) {
    if (dateStr == null) return null;
    final s = dateStr.toString();
    if (s.length >= 4) return s.substring(0, 4);
    return null;
  }
}