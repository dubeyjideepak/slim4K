import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/video_task.dart';

class ProjectScanResult {
  final String sourceDir;
  final String targetDir;
  final List<VideoTask> videoTasks;
  final List<File> nonVideoFiles;
  final int totalSourceBytes;

  ProjectScanResult({
    required this.sourceDir,
    required this.targetDir,
    required this.videoTasks,
    required this.nonVideoFiles,
    required this.totalSourceBytes,
  });
}

class CompressionEngine {
  Process? _activeProcess;
  bool _isCancelled = false;

  static const Set<String> videoExtensions = {
    '.mp4',
    '.mov',
    '.mkv',
    '.m4v',
    '.avi',
    '.mts',
    '.m2ts',
    '.wmv',
    '.flv',
  };

  static String resolveExecutable(String name) {
    if (Platform.isWindows) return name;
    final candidates = [
      '/opt/homebrew/bin/$name',
      '/usr/local/bin/$name',
      '/usr/bin/$name',
      '/bin/$name',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return name;
  }

  /// Returns the hardware acceleration encoder name for the current platform
  Future<String> getAvailableHardwareEncoder() async {
    if (Platform.isMacOS) {
      return 'hevc_videotoolbox';
    } else if (Platform.isWindows) {
      try {
        final ffmpeg = resolveExecutable('ffmpeg');
        final result = await Process.run(ffmpeg, ['-encoders']);
        final out = result.stdout.toString();
        if (out.contains('hevc_nvenc')) return 'hevc_nvenc';
        if (out.contains('hevc_qsv')) return 'hevc_qsv';
        if (out.contains('hevc_amf')) return 'hevc_amf';
      } catch (_) {}
      return 'libx265';
    } else if (Platform.isLinux) {
      try {
        final ffmpeg = resolveExecutable('ffmpeg');
        final result = await Process.run(ffmpeg, ['-encoders']);
        final out = result.stdout.toString();
        if (out.contains('hevc_vaapi')) return 'hevc_vaapi';
        if (out.contains('hevc_nvenc')) return 'hevc_nvenc';
      } catch (_) {}
      return 'libx265';
    } else if (Platform.isAndroid) {
      return 'hevc_mediacodec';
    }
    return 'libx265';
  }

  /// Returns the fastest H.264 proxy encoder
  Future<String> getAvailableProxyEncoder() async {
    if (Platform.isMacOS) {
      return 'h264_videotoolbox';
    } else if (Platform.isWindows) {
      try {
        final ffmpeg = resolveExecutable('ffmpeg');
        final result = await Process.run(ffmpeg, ['-encoders']);
        final out = result.stdout.toString();
        if (out.contains('h264_nvenc')) return 'h264_nvenc';
        if (out.contains('h264_qsv')) return 'h264_qsv';
      } catch (_) {}
      return 'libx264';
    } else if (Platform.isAndroid) {
      return 'h264_mediacodec';
    }
    return 'libx264';
  }

  /// Probes video duration, width, height, audio using ffprobe
  Future<Map<String, dynamic>> probeVideo(String filePath) async {
    int durationMs = 0;
    int width = 3840;
    int height = 2160;
    double fps = 30.0;
    int bitrateKbps = 100000;
    bool hasAudio = false;
    String audioCodec = '';
    int audioChannels = 2;

    try {
      final ffprobe = resolveExecutable('ffprobe');
      final result = await Process.run(ffprobe, [
        '-v', 'error',
        '-show_entries', 'format=duration,bit_rate:stream=index,codec_name,codec_type,width,height,r_frame_rate,channels',
        '-of', 'json',
        filePath,
      ]);

      if (result.exitCode == 0) {
        final data = jsonDecode(result.stdout as String);
        if (data['format'] != null) {
          final durSec = double.tryParse(data['format']['duration']?.toString() ?? '0') ?? 0;
          durationMs = (durSec * 1000).round();
          final bRate = int.tryParse(data['format']['bit_rate']?.toString() ?? '0') ?? 0;
          if (bRate > 0) bitrateKbps = (bRate / 1000).round();
        }
        if (data['streams'] != null && (data['streams'] as List).isNotEmpty) {
          final streams = data['streams'] as List;
          for (final stream in streams) {
            final type = stream['codec_type']?.toString();
            if (type == 'video' && width == 3840 && height == 2160) {
              width = int.tryParse(stream['width']?.toString() ?? '3840') ?? 3840;
              height = int.tryParse(stream['height']?.toString() ?? '2160') ?? 2160;
              final rFps = stream['r_frame_rate']?.toString() ?? '30/1';
              if (rFps.contains('/')) {
                final parts = rFps.split('/');
                final num = double.tryParse(parts[0]) ?? 30.0;
                final den = double.tryParse(parts[1]) ?? 1.0;
                fps = den > 0 ? num / den : 30.0;
              }
            } else if (type == 'audio') {
              hasAudio = true;
              audioCodec = stream['codec_name']?.toString() ?? '';
              audioChannels = int.tryParse(stream['channels']?.toString() ?? '2') ?? 2;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('ffprobe error or not available: $e');
    }

    return {
      'durationMs': durationMs,
      'width': width,
      'height': height,
      'fps': fps,
      'bitrateKbps': bitrateKbps,
      'hasAudio': hasAudio,
      'audioCodec': audioCodec,
      'audioChannels': audioChannels,
    };
  }

  /// Scans a project folder recursively, identifies video & non-video files,
  /// and builds the mirror destination directory paths.
  Future<ProjectScanResult> scanProjectFolder(String sourceDirPath) async {
    final sourceDir = Directory(sourceDirPath);
    if (!await sourceDir.exists()) {
      throw Exception('Source directory does not exist: $sourceDirPath');
    }

    final parentDir = sourceDir.parent.path;
    final folderName = p.basename(sourceDirPath);
    final targetDirPath = p.join(parentDir, '${folderName}_SlimArchive');

    final List<VideoTask> videoTasks = [];
    final List<File> nonVideoFiles = [];
    int totalBytes = 0;

    await for (final entity in sourceDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        final size = await entity.length();
        totalBytes += size;
        final relPath = p.relative(entity.path, from: sourceDirPath);

        if (videoExtensions.contains(ext)) {
          final task = VideoTask(
            id: DateTime.now().microsecondsSinceEpoch.toString() + relPath.hashCode.toString(),
            inputPath: entity.path,
            fileName: p.basename(entity.path),
            inputFileSize: size,
            relativeSubPath: relPath,
          );
          videoTasks.add(task);
        } else {
          nonVideoFiles.add(entity);
        }
      }
    }

    return ProjectScanResult(
      sourceDir: sourceDirPath,
      targetDir: targetDirPath,
      videoTasks: videoTasks,
      nonVideoFiles: nonVideoFiles,
      totalSourceBytes: totalBytes,
    );
  }

  /// Safely copy a non-video asset to mirrored target path
  Future<void> copyNonVideoFile({
    required File sourceFile,
    required String sourceRoot,
    required String targetRoot,
  }) async {
    final relPath = p.relative(sourceFile.path, from: sourceRoot);
    final targetPath = p.join(targetRoot, relPath);
    final targetDir = Directory(p.dirname(targetPath));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    await sourceFile.copy(targetPath);
  }

  /// Performs hardware-accelerated 4K HEVC compression with timecode preservation
  Future<String> compressVideo({
    required VideoTask task,
    String? customOutputPath,
    required void Function(
      double progress,
      double currentFps,
      double speedMultiplier,
      Duration? eta,
    ) onProgress,
  }) async {
    _isCancelled = false;

    // Determine output path
    String outputPath;
    if (customOutputPath != null) {
      outputPath = customOutputPath;
      final outDir = Directory(p.dirname(outputPath));
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }
    } else {
      String outputDir;
      final inputDir = Directory(p.dirname(task.inputPath));
      bool canWriteInput = false;
      try {
        if (await inputDir.exists()) {
          final testFile = File(p.join(inputDir.path, '.test_write_${DateTime.now().millisecondsSinceEpoch}'));
          await testFile.writeAsString('test');
          await testFile.delete();
          canWriteInput = true;
        }
      } catch (_) {
        canWriteInput = false;
      }

      if (canWriteInput) {
        outputDir = inputDir.path;
      } else if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        outputDir = extDir?.path ?? (await getApplicationDocumentsDirectory()).path;
      } else {
        final docDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        outputDir = docDir.path;
      }
      final baseName = p.basenameWithoutExtension(task.inputPath);
      outputPath = p.join(outputDir, '${baseName}_slim.mp4');
    }

    // Remove old output if exists
    final oldFile = File(outputPath);
    if (await oldFile.exists()) {
      await oldFile.delete();
    }

    final encoder = await getAvailableHardwareEncoder();
    final bitrateK = task.targetBitrateKbps;

    // Build FFmpeg command arguments
    final List<String> args = [
      '-y',
      '-i', task.inputPath,
      '-map', '0:v:0',
      '-map', '0:a?',
      '-map_metadata', '0',
      '-copyts',
    ];

    // Hardware encoder arguments
    if (encoder == 'hevc_videotoolbox') {
      args.addAll([
        '-c:v', 'hevc_videotoolbox',
        '-b:v', '${bitrateK}k',
        '-maxrate', '${(bitrateK * 1.5).round()}k',
        '-bufsize', '${(bitrateK * 2).round()}k',
        '-tag:v', 'hvc1',
        '-color_primaries', 'bt709',
        '-color_trc', 'bt709',
        '-colorspace', 'bt709',
      ]);
    } else if (encoder == 'hevc_nvenc') {
      args.addAll([
        '-c:v', 'hevc_nvenc',
        '-b:v', '${bitrateK}k',
        '-preset', 'p5',
        '-rc', 'vbr',
        '-tag:v', 'hvc1',
      ]);
    } else if (encoder == 'hevc_mediacodec') {
      args.addAll([
        '-c:v', 'hevc_mediacodec',
        '-b:v', '${bitrateK}k',
        '-tag:v', 'hvc1',
      ]);
    } else {
      // Fallback fast CPU HEVC
      args.addAll([
        '-c:v', 'libx265',
        '-preset', 'fast',
        '-b:v', '${bitrateK}k',
        '-tag:v', 'hvc1',
      ]);
    }

    // Audio handling: Studio grade preserving all channels / passthrough
    if (task.preserveOriginalAudio) {
      args.addAll([
        '-c:a', 'aac',
        '-b:a', '320k', // Studio Broadcast 320 kbps multi-channel transparent
      ]);
    } else {
      args.addAll([
        '-c:a', 'aac',
        '-b:a', '160k',
      ]);
    }

    args.addAll([
      '-movflags', '+faststart+use_metadata_tags',
      outputPath,
    ]);

    final ffmpeg = resolveExecutable('ffmpeg');
    debugPrint('Executing FFmpeg: $ffmpeg ${args.join(' ')}');

    final process = await Process.start(ffmpeg, args);
    _activeProcess = process;

    final totalDurationSec = task.durationMs > 0 ? (task.durationMs / 1000.0) : 0.0;

    final timeRegex = RegExp(r'time=(\d+):(\d+):(\d+\.?\d*)');
    final fpsRegex = RegExp(r'fps=\s*(\d+\.?\d*)');
    final speedRegex = RegExp(r'speed=\s*(\d+\.?\d*)x');

    process.stderr.transform(utf8.decoder).listen((line) {
      if (_isCancelled) return;

      double? currentSec;
      final timeMatch = timeRegex.firstMatch(line);
      if (timeMatch != null) {
        final hours = double.tryParse(timeMatch.group(1)!) ?? 0;
        final mins = double.tryParse(timeMatch.group(2)!) ?? 0;
        final secs = double.tryParse(timeMatch.group(3)!) ?? 0;
        currentSec = (hours * 3600) + (mins * 60) + secs;
      }

      double currentFps = 0.0;
      final fpsMatch = fpsRegex.firstMatch(line);
      if (fpsMatch != null) {
        currentFps = double.tryParse(fpsMatch.group(1)!) ?? 0.0;
      }

      double speedMultiplier = 1.0;
      final speedMatch = speedRegex.firstMatch(line);
      if (speedMatch != null) {
        speedMultiplier = double.tryParse(speedMatch.group(1)!) ?? 1.0;
      }

      double progress = 0.0;
      Duration? eta;

      if (currentSec != null && totalDurationSec > 0) {
        progress = (currentSec / totalDurationSec).clamp(0.0, 0.99);
        final remainingSec = totalDurationSec - currentSec;
        if (speedMultiplier > 0 && remainingSec > 0) {
          eta = Duration(seconds: (remainingSec / speedMultiplier).round());
        }
      }

      onProgress(progress, currentFps, speedMultiplier, eta);
    });

    final exitCode = await process.exitCode;
    _activeProcess = null;

    if (_isCancelled) {
      if (await File(outputPath).exists()) {
        await File(outputPath).delete();
      }
      throw Exception('Compression cancelled by user');
    }

    if (exitCode != 0) {
      throw Exception('FFmpeg failed with exit code $exitCode');
    }

    // Verify output file exists and has size
    final outFile = File(outputPath);
    if (!await outFile.exists() || await outFile.length() == 0) {
      throw Exception('Output video file was not generated or is empty');
    }

    return outputPath;
  }

  /// Generates a lightweight 1080p editing proxy alongside the archive
  Future<String> generateProxyVideo({
    required VideoTask task,
    String? customProxyPath,
  }) async {
    _isCancelled = false;

    String proxyPath;
    if (customProxyPath != null) {
      proxyPath = customProxyPath;
    } else {
      final outDir = p.dirname(task.outputPath ?? task.inputPath);
      final baseName = p.basenameWithoutExtension(task.inputPath);
      proxyPath = p.join(outDir, '${baseName}_proxy.mp4');
    }

    final oldFile = File(proxyPath);
    if (await oldFile.exists()) {
      await oldFile.delete();
    }

    final proxyEncoder = await getAvailableProxyEncoder();
    final ffmpeg = resolveExecutable('ffmpeg');

    final List<String> args = [
      '-y',
      '-i', task.inputPath,
      '-vf', 'scale=-2:1080',
      '-map', '0:v:0',
      '-map', '0:a?',
      '-map_metadata', '0',
      '-c:v', proxyEncoder,
      '-b:v', '2500k',
      '-c:a', 'aac',
      '-b:a', '128k',
      '-movflags', '+faststart',
      proxyPath,
    ];

    debugPrint('Generating Proxy: $ffmpeg ${args.join(' ')}');
    final process = await Process.start(ffmpeg, args);
    _activeProcess = process;
    final exitCode = await process.exitCode;
    _activeProcess = null;

    if (exitCode != 0 || !await File(proxyPath).exists()) {
      throw Exception('Failed to generate 1080p proxy file');
    }

    return proxyPath;
  }

  /// Safety Verification: checks video container integrity and stream readability
  Future<bool> verifyVideo(String filePath) async {
    final file = File(filePath);
    if (!await file.exists() || await file.length() == 0) {
      return false;
    }

    try {
      final ffmpeg = resolveExecutable('ffmpeg');
      // Decode initial 5 seconds into null muxer to test headers and frame decodability
      final result = await Process.run(ffmpeg, [
        '-v', 'error',
        '-i', filePath,
        '-t', '5',
        '-f', 'null',
        '-',
      ]);
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Verification error: $e');
      return false;
    }
  }

  /// Safe Trash: Moves original file to System Trash (never hard-deletes!)
  Future<bool> moveToTrash(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return false;

    if (Platform.isMacOS) {
      try {
        final script = 'tell application "Finder" to delete POSIX file "$filePath"';
        final result = await Process.run('osascript', ['-e', script]);
        return result.exitCode == 0;
      } catch (e) {
        debugPrint('AppleScript trash error: $e');
      }
    }

    // Fallback: move to ~/.Trash on Unix if available
    try {
      final home = Platform.environment['HOME'];
      if (home != null) {
        final trashDir = Directory(p.join(home, '.Trash'));
        if (await trashDir.exists()) {
          final target = p.join(trashDir.path, p.basename(filePath));
          await file.rename(target);
          return true;
        }
      }
    } catch (_) {}

    return false;
  }

  void cancel() {
    _isCancelled = true;
    _activeProcess?.kill(ProcessSignal.sigkill);
    _activeProcess = null;
  }
}
