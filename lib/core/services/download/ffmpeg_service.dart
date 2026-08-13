import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';

/// FFmpeg helpers copied from the SpotiFLAC Mobile download pipeline so the
/// post-download conversion behavior is identical (M4A/DASH -> FLAC, and
/// M4A -> requested lossy format for HIGH quality Tidal downloads).
class FFmpegService {
  static Future<FFmpegResult> _execute(String command) async {
    try {
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      final output = await session.getOutput() ?? '';

      return FFmpegResult(
        success: ReturnCode.isSuccess(returnCode),
        returnCode: returnCode?.getValue() ?? -1,
        output: output,
      );
    } catch (e) {
      debugPrint('[FFmpeg] execute error: $e');
      return FFmpegResult(success: false, returnCode: -1, output: e.toString());
    }
  }

  static String _buildOutputPath(String inputPath, String extension) {
    final normalizedExt = extension.startsWith('.') ? extension : '.$extension';
    final inputFile = File(inputPath);
    final dir = inputFile.parent.path;
    final filename = inputFile.uri.pathSegments.last;
    final dotIndex = filename.lastIndexOf('.');
    final baseName = dotIndex > 0 ? filename.substring(0, dotIndex) : filename;
    var outputPath = '$dir${Platform.pathSeparator}$baseName$normalizedExt';

    if (outputPath == inputPath) {
      outputPath =
          '$dir${Platform.pathSeparator}${baseName}_converted$normalizedExt';
    }
    return outputPath;
  }

  static bool _sameLocalPath(String first, String second) {
    final firstPath = File(first).absolute.path;
    final secondPath = File(second).absolute.path;
    return Platform.isWindows
        ? firstPath.toLowerCase() == secondPath.toLowerCase()
        : firstPath == secondPath;
  }

  static Future<String> _uniqueConversionPath(String requestedPath) async {
    if (!await File(requestedPath).exists()) return requestedPath;
    final file = File(requestedPath);
    final fileName = file.uri.pathSegments.last;
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final extension = dotIndex > 0 ? fileName.substring(dotIndex) : '';
    for (var index = 2; ; index++) {
      final candidate =
          '${file.parent.path}${Platform.pathSeparator}$baseName ($index)$extension';
      if (!await File(candidate).exists()) return candidate;
    }
  }

  static Future<_ConversionOutputPlan> _conversionOutputPlan(
    String inputPath,
    String extension, {
    required bool deleteOriginal,
  }) async {
    final normalizedExt = extension.startsWith('.') ? extension : '.$extension';
    final inputFile = File(inputPath);
    final fileName = inputFile.uri.pathSegments.last;
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final requestedPath =
        '${inputFile.parent.path}${Platform.pathSeparator}$baseName$normalizedExt';

    if (_sameLocalPath(requestedPath, inputPath) && deleteOriginal) {
      final token = DateTime.now().microsecondsSinceEpoch;
      return _ConversionOutputPlan(
        workingPath:
            '${inputFile.parent.path}${Platform.pathSeparator}.$baseName.spotiflac-$token$normalizedExt',
        finalPath: inputPath,
      );
    }

    final finalPath = await _uniqueConversionPath(requestedPath);
    return _ConversionOutputPlan(workingPath: finalPath, finalPath: finalPath);
  }

  static Future<void> _cleanupConversionOutput(
    _ConversionOutputPlan plan,
  ) async {
    try {
      final output = File(plan.workingPath);
      if (await output.exists()) await output.delete();
    } catch (e) {
      debugPrint('[FFmpeg] Failed to clean conversion output: $e');
    }
  }

  static Future<String?> _finalizeConversionOutput({
    required _ConversionOutputPlan plan,
    required String inputPath,
    required bool deleteOriginal,
  }) async {
    if (!await File(plan.workingPath).exists()) {
      debugPrint('[FFmpeg] Converted output is missing: ${plan.workingPath}');
      return null;
    }

    if (plan.requiresPromotion) {
      final source = File(inputPath);
      final backupPath =
          '$inputPath.spotiflac-backup-${DateTime.now().microsecondsSinceEpoch}';
      final backup = File(backupPath);
      var sourceMovedToBackup = false;
      try {
        if (await source.exists()) {
          await source.rename(backupPath);
          sourceMovedToBackup = true;
        }
        await File(plan.workingPath).rename(plan.finalPath);
      } catch (e) {
        debugPrint('[FFmpeg] Failed to replace original after conversion: $e');
        try {
          if (sourceMovedToBackup &&
              !await source.exists() &&
              await backup.exists()) {
            await backup.rename(inputPath);
          }
        } catch (restoreError) {
          debugPrint('[FFmpeg] Failed to restore original backup: $restoreError');
        }
        await _cleanupConversionOutput(plan);
        return null;
      }
      try {
        if (await backup.exists()) await backup.delete();
      } catch (e) {
        debugPrint('[FFmpeg] Converted file ready but backup cleanup failed: $e');
      }
      return plan.finalPath;
    }

    if (deleteOriginal && !_sameLocalPath(inputPath, plan.finalPath)) {
      try {
        final source = File(inputPath);
        if (await source.exists()) await source.delete();
      } catch (e) {
        debugPrint('[FFmpeg] Failed to delete original after conversion: $e');
      }
    }
    return plan.finalPath;
  }

  /// Probes the primary audio codec (e.g. "flac", "opus", "aac", "alac").
  static Future<String?> probePrimaryAudioCodec(String filePath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(filePath);
      final info = session.getMediaInformation();
      if (info == null) return null;

      for (final stream in info.getStreams()) {
        final props = stream.getAllProperties() ?? const <String, dynamic>{};
        if (props['codec_type']?.toString() != 'audio') continue;
        final codec = props['codec_name']?.toString().trim().toLowerCase();
        return codec == null || codec.isEmpty ? null : codec;
      }
    } catch (e) {
      debugPrint('[FFmpeg] Audio codec probe failed for $filePath: $e');
    }
    return null;
  }

  static bool isLosslessAudioCodec(String? codec) {
    final normalized = codec?.trim().toLowerCase().replaceAll('-', '_') ?? '';
    if (normalized.isEmpty) return false;
    if (normalized.startsWith('pcm_')) return true;
    return const {
      'alac',
      'flac',
      'wavpack',
      'ape',
      'tta',
      'mlp',
      'truehd',
      'shorten',
    }.contains(normalized);
  }

  /// True when [filePath] starts with the native FLAC magic bytes (`fLaC`),
  /// distinguishing a real FLAC file from a FLAC-in-MP4 container carrying a
  /// `.flac` extension.
  static Future<bool> isNativeFlacFile(String filePath) async {
    try {
      final raf = await File(filePath).open();
      try {
        final header = await raf.read(4);
        return header.length == 4 &&
            header[0] == 0x66 && // 'f'
            header[1] == 0x4C && // 'L'
            header[2] == 0x61 && // 'a'
            header[3] == 0x43; // 'C'
      } finally {
        await raf.close();
      }
    } catch (e) {
      debugPrint('[FFmpeg] Native FLAC magic probe failed for $filePath: $e');
      return false;
    }
  }

  static Future<String?> convertM4aToFlac(String inputPath) async {
    final outputPath = _buildOutputPath(inputPath, '.flac');

    final command =
        '-v error -xerror -i "$inputPath" -c:a flac -compression_level 8 "$outputPath" -y';

    final result = await _execute(command);

    if (result.success) {
      try {
        await File(inputPath).delete();
      } catch (_) {}
      return outputPath;
    }

    debugPrint('[FFmpeg] M4A to FLAC conversion failed: ${result.output}');
    return null;
  }

  static Future<String?> convertM4aToLossy(
    String inputPath, {
    required String format,
    String? bitrate,
    bool deleteOriginal = true,
  }) async {
    final normalizedFormat = format.toLowerCase();
    String bitrateValue = normalizedFormat == 'opus' ? '128k' : '320k';
    if (bitrate != null && bitrate.contains('_')) {
      final parts = bitrate.split('_');
      if (parts.length == 2) {
        bitrateValue = '${parts[1]}k';
      }
    }

    final extension = switch (normalizedFormat) {
      'opus' => '.opus',
      'aac' || 'm4a' => '.m4a',
      _ => '.mp3',
    };
    final outputPlan = await _conversionOutputPlan(
      inputPath,
      extension,
      deleteOriginal: deleteOriginal,
    );
    final outputPath = outputPlan.workingPath;

    String command;
    if (normalizedFormat == 'opus') {
      command =
          '-v error -hide_banner -i "$inputPath" -codec:a libopus -b:a $bitrateValue -vbr on -compression_level 10 -map 0:a "$outputPath" -y';
    } else if (normalizedFormat == 'aac' || normalizedFormat == 'm4a') {
      command =
          '-v error -hide_banner -i "$inputPath" -codec:a aac -b:a $bitrateValue -map 0:a -f mp4 "$outputPath" -y';
    } else {
      command =
          '-v error -hide_banner -i "$inputPath" -codec:a libmp3lame -b:a $bitrateValue -map 0:a -id3v2_version 3 "$outputPath" -y';
    }

    final result = await _execute(command);

    if (result.success) {
      return _finalizeConversionOutput(
        plan: outputPlan,
        inputPath: inputPath,
        deleteOriginal: deleteOriginal,
      );
    }

    debugPrint('[FFmpeg] M4A to $normalizedFormat conversion failed: ${result.output}');
    await _cleanupConversionOutput(outputPlan);
    return null;
  }

  static Future<bool> isAvailable() async {
    try {
      final version = await FFmpegKitConfig.getFFmpegVersion();
      return version?.isNotEmpty ?? false;
    } catch (e) {
      return false;
    }
  }
}

class FFmpegResult {
  final bool success;
  final int returnCode;
  final String output;

  const FFmpegResult({
    required this.success,
    required this.returnCode,
    required this.output,
  });
}

class _ConversionOutputPlan {
  final String workingPath;
  final String finalPath;

  const _ConversionOutputPlan({
    required this.workingPath,
    required this.finalPath,
  });

  bool get requiresPromotion => workingPath != finalPath;
}