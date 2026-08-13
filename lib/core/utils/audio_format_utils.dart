/// Audio format/quality helpers copied from the SpotiFLAC Mobile download
/// pipeline so u_player's post-download handling matches it exactly.

String? normalizeOptionalString(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

String? audioFormatForPath(String? filePath, {String? fileName}) {
  final candidates = <String>[
    if (filePath != null) filePath,
    if (fileName != null) fileName,
  ];
  for (final candidate in candidates) {
    final lower = candidate.trim().toLowerCase();
    if (lower.endsWith('.opus') || lower.endsWith('.ogg')) return 'OPUS';
    if (lower.endsWith('.mp3')) return 'MP3';
    if (lower.endsWith('.aac')) return 'AAC';
    if (lower.endsWith('.m4a') || lower.endsWith('.mp4')) return 'M4A';
  }
  return null;
}

String? normalizeAudioFormatValue(String? value) {
  final normalized = normalizeOptionalString(
    value,
  )?.toLowerCase().replaceAll('-', '_');
  return switch (normalized) {
    'flac' => 'flac',
    'alac' => 'alac',
    'wav' || 'wave' => 'wav',
    'aiff' || 'aif' || 'aifc' => 'aiff',
    'aac' || 'mp4a' => 'aac',
    'eac3' || 'ec_3' => 'eac3',
    'ac3' || 'ac_3' => 'ac3',
    'ac4' || 'ac_4' => 'ac4',
    'mp3' => 'mp3',
    'opus' || 'ogg' => 'opus',
    'm4a' || 'mp4' => 'm4a',
    _ => null,
  };
}

bool isLossyAudioFormat(String? value) {
  return const {
    'aac',
    'eac3',
    'ac3',
    'ac4',
    'mp3',
    'opus',
    'm4a',
  }.contains(normalizeAudioFormatValue(value));
}

String lossyFormatForSetting(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.startsWith('opus')) return 'opus';
  if (normalized.startsWith('aac') || normalized.startsWith('m4a')) {
    return 'aac';
  }
  return 'mp3';
}

String lossyExtensionForFormat(String format) {
  return switch (format) {
    'opus' => '.opus',
    'aac' => '.m4a',
    _ => '.mp3',
  };
}

String metadataFormatForLossyFormat(String format) {
  return format == 'aac' ? 'm4a' : format;
}

String displayFormatForLossyFormat(String format) {
  return format == 'aac' ? 'AAC' : format.toUpperCase();
}

String qualityVariantStagingLabel(String itemId) {
  var hash = 0x811c9dc5;
  for (final byte in itemId.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return 'qv_${hash.toRadixString(16).padLeft(8, '0')}';
}