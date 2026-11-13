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

class QuotaHardLimitExceededException implements Exception {
  final int totalProcessedBytes;
  final int hardLimitBytes;

  const QuotaHardLimitExceededException({
    required this.totalProcessedBytes,
    required this.hardLimitBytes,
  });

  @override
  String toString() => 'Trial processing hard limit (2.5 GB) exceeded during file slimming.';
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
    final exeName = Platform.isWindows ? '$name.exe' : name;

    // 1. Check folder where the running app binary is located (e.g. C:\Program Files\Slim4K\)
    try {
      final appDir = p.dirname(Platform.resolvedExecutable);
      final inAppDir = p.join(appDir, exeName);
      if (File(inAppDir).existsSync()) return inAppDir;

      final inTools = p.join(appDir, 'tools', exeName);
      if (File(inTools).existsSync()) return inTools;

      final inBin = p.join(appDir, 'bin', exeName);
      if (File(inBin).existsSync()) return inBin;
    } catch (_) {}

    // 2. Candidate system paths on Windows
    if (Platform.isWindows) {
      final winCandidates = [
        r'C:\ffmpeg\bin\' + exeName,
        r'C:\Program Files\ffmpeg\bin\' + exeName,
        r'C:\ProgramData\chocolatey\bin\' + exeName,
      ];
      for (final c in winCandidates) {
        if (File(c).existsSync()) return c;
      }
      return exeName;
    }

    // 3. Candidate Unix / macOS paths
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

  static final Map<String, bool> _encoderCache = {};

  /// Probes whether a specific video encoder actually executes on this machine's hardware
  Future<bool> _testEncoder(String encoderName) async {
    if (_encoderCache.containsKey(encoderName)) {
      return _encoderCache[encoderName]!;
    }
    try {
      final ffmpeg = resolveExecutable('ffmpeg');
      // Use 256x256 resolution: NVIDIA NVENC requires width >= 129 pixels,
      // and Intel QSV / AMD AMF require standard macroblock-aligned dimensions.
      final result = await Process.run(ffmpeg, [
        '-f', 'lavfi',
        '-i', 'color=c=black:s=256x256:d=0.04',
        '-c:v', encoderName,
        '-f', 'null',
        '-',
      ]).timeout(const Duration(seconds: 4));

      final works = result.exitCode == 0;
      debugPrint('Probing hardware encoder ($encoderName): works=$works (exitCode=${result.exitCode})');
      _encoderCache[encoderName] = works;
      return works;
    } catch (e) {
      debugPrint('Probing hardware encoder ($encoderName) failed: $e');
      _encoderCache[encoderName] = false;
      return false;
    }
  }

  /// Returns the hardware acceleration encoder name for the current platform
  Future<String> getAvailableHardwareEncoder() async {
    if (Platform.isMacOS) {
      if (await _testEncoder('hevc_videotoolbox')) return 'hevc_videotoolbox';
    } else if (Platform.isWindows) {
      if (await _testEncoder('hevc_nvenc')) return 'hevc_nvenc';
      if (await _testEncoder('hevc_qsv')) return 'hevc_qsv';
      if (await _testEncoder('hevc_amf')) return 'hevc_amf';
    } else if (Platform.isLinux) {
      if (await _testEncoder('hevc_vaapi')) return 'hevc_vaapi';
      if (await _testEncoder('hevc_nvenc')) return 'hevc_nvenc';
    } else if (Platform.isAndroid) {
      return 'hevc_mediacodec';
    }
    return 'libx265';
  }

  /// Returns the fastest H.264 proxy encoder
  Future<String> getAvailableProxyEncoder() async {
    if (Platform.isMacOS) {
      if (await _testEncoder('h264_videotoolbox')) return 'h264_videotoolbox';
    } else if (Platform.isWindows) {
      if (await _testEncoder('h264_nvenc')) return 'h264_nvenc';
      if (await _testEncoder('h264_qsv')) return 'h264_qsv';
      if (await _testEncoder('h264_amf')) return 'h264_amf';
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
        final baseWithoutExt = p.basenameWithoutExtension(entity.path).toLowerCase();

        // Skip files that were already slimmed or proxies
        if (baseWithoutExt.endsWith('_slim') || baseWithoutExt.endsWith('_slim4k') || baseWithoutExt.endsWith('_proxy')) {
          continue;
        }

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

  Future<String> _resolveOutputPath(VideoTask task, String? customOutputPath) async {
    if (customOutputPath != null) {
      final outDir = Directory(p.dirname(customOutputPath));
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }
      return customOutputPath;
    }

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
    return p.join(outputDir, '${baseName}_slim.mp4');
  }

  String _resolveProxyPath(VideoTask task, String? customProxyPath) {
    if (customProxyPath != null) return customProxyPath;
    final outDir = p.dirname(task.outputPath ?? task.inputPath);
    final baseName = p.basenameWithoutExtension(task.inputPath);
    return p.join(outDir, '${baseName}_proxy.mp4');
  }

  /// Performs 4K HEVC compression with automatic hardware acceleration and resilient CPU fallback
  Future<String> compressVideo({
    required VideoTask task,
    String? customOutputPath,
    bool Function(double currentProgress)? onLiveProgressCheck,
    required void Function(
      double progress,
      double currentFps,
      double speedMultiplier,
      Duration? eta,
    ) onProgress,
  }) async {
    _isCancelled = false;

    final outputPath = await _resolveOutputPath(task, customOutputPath);
    final preferredEncoder = await getAvailableHardwareEncoder();

    try {
      return await _executeCompression(
        task: task,
        outputPath: outputPath,
        encoder: preferredEncoder,
        onLiveProgressCheck: onLiveProgressCheck,
        onProgress: onProgress,
      );
    } catch (e) {
      if (e is QuotaHardLimitExceededException) rethrow;
      if (_isCancelled) rethrow;

      // If hardware encoder failed on this machine (e.g. driver mismatch, GPU memory),
      // seamlessly fall back to universal CPU libx265 so user compression always succeeds!
      if (preferredEncoder != 'libx265') {
        debugPrint('Hardware encoder ($preferredEncoder) failed: $e. Retrying with universal CPU libx265...');
        final partial = File(outputPath);
        if (await partial.exists()) {
          try { await partial.delete(); } catch (_) {}
        }
        return await _executeCompression(
          task: task,
          outputPath: outputPath,
          encoder: 'libx265',
          onLiveProgressCheck: onLiveProgressCheck,
          onProgress: onProgress,
        );
      }
      rethrow;
    }
  }

  Future<String> _executeCompression({
    required VideoTask task,
    required String outputPath,
    required String encoder,
    bool Function(double currentProgress)? onLiveProgressCheck,
    required void Function(
      double progress,
      double currentFps,
      double speedMultiplier,
      Duration? eta,
    ) onProgress,
  }) async {
    // Remove old output if exists
    final oldFile = File(outputPath);
    if (await oldFile.exists()) {
      await oldFile.delete();
    }

    final bitrateK = task.targetBitrateKbps;

    // Build FFmpeg command arguments
    final List<String> args = [
      '-y',
      '-i', task.inputPath,
      '-map', '0:v:0',
      '-map', '0:a?',
      '-map_metadata', '0',
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
        '-pix_fmt', 'yuv420p',
        '-b:v', '${bitrateK}k',
        '-preset', 'p4',
        '-rc', 'vbr',
        '-tag:v', 'hvc1',
      ]);
    } else if (encoder == 'hevc_qsv') {
      args.addAll([
        '-c:v', 'hevc_qsv',
        '-pix_fmt', 'nv12',
        '-b:v', '${bitrateK}k',
        '-preset', 'medium',
        '-tag:v', 'hvc1',
      ]);
    } else if (encoder == 'hevc_amf') {
      args.addAll([
        '-c:v', 'hevc_amf',
        '-pix_fmt', 'nv12',
        '-b:v', '${bitrateK}k',
        '-quality', 'balanced',
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
        '-pix_fmt', 'yuv420p',
        '-preset', 'fast',
        '-b:v', '${bitrateK}k',
        '-tag:v', 'hvc1',
      ]);
    }

    // Audio handling: Studio grade preserving all channels / passthrough
    if (task.preserveOriginalAudio) {
      args.addAll([
        '-c:a', 'aac',
        '-b:a', '320k',
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
    debugPrint('Executing FFmpeg ($encoder): $ffmpeg ${args.join(' ')}');

    final process = await Process.start(ffmpeg, args);
    _activeProcess = process;

    final totalDurationSec = task.durationMs > 0 ? (task.durationMs / 1000.0) : 0.0;

    final timeRegex = RegExp(r'time=(\d+):(\d+):(\d+\.?\d*)');
    final fpsRegex = RegExp(r'fps=\s*(\d+\.?\d*)');
    final speedRegex = RegExp(r'speed=\s*(\d+\.?\d*)x');

    final List<String> recentStderr = [];
    double lastKnownProgress = 0.0;
    double lastKnownFps = 0.0;
    double lastKnownSpeed = 1.0;
    Duration? lastKnownEta;
    bool wasHardLimitExceeded = false;

    process.stderr.transform(utf8.decoder).listen((line) {
      if (_isCancelled) return;

      recentStderr.add(line);
      if (recentStderr.length > 30) recentStderr.removeAt(0);

      final timeMatch = timeRegex.firstMatch(line);
      if (timeMatch != null && totalDurationSec > 0) {
        final hours = double.tryParse(timeMatch.group(1)!) ?? 0;
        final mins = double.tryParse(timeMatch.group(2)!) ?? 0;
        final secs = double.tryParse(timeMatch.group(3)!) ?? 0;
        final currentSec = (hours * 3600) + (mins * 60) + secs;

        final parsedProgress = (currentSec / totalDurationSec).clamp(0.0, 0.99);
        if (parsedProgress > lastKnownProgress) {
          lastKnownProgress = parsedProgress;
        }

        final fpsMatch = fpsRegex.firstMatch(line);
        if (fpsMatch != null) {
          lastKnownFps = double.tryParse(fpsMatch.group(1)!) ?? lastKnownFps;
        }

        final speedMatch = speedRegex.firstMatch(line);
        if (speedMatch != null) {
          lastKnownSpeed = double.tryParse(speedMatch.group(1)!) ?? lastKnownSpeed;
        }

        final remainingSec = totalDurationSec - currentSec;
        if (lastKnownSpeed > 0 && remainingSec > 0) {
          lastKnownEta = Duration(seconds: (remainingSec / lastKnownSpeed).round());
        }

        onProgress(lastKnownProgress, lastKnownFps, lastKnownSpeed, lastKnownEta);

        // Enforce live hard trial limit guard (2.5 GB max during live compression)
        if (onLiveProgressCheck != null && !onLiveProgressCheck(lastKnownProgress)) {
          wasHardLimitExceeded = true;
          _isCancelled = true;
          process.kill(ProcessSignal.sigkill);
        }
      }
    });

    final exitCode = await process.exitCode;
    _activeProcess = null;

    if (_isCancelled) {
      if (await File(outputPath).exists()) {
        try { await File(outputPath).delete(); } catch (_) {}
      }

      // Check if cancellation was triggered by live hard trial limit guard
      if (wasHardLimitExceeded || (onLiveProgressCheck != null && !onLiveProgressCheck(lastKnownProgress))) {
        throw QuotaHardLimitExceededException(
          totalProcessedBytes: (task.inputFileSize * lastKnownProgress).round(),
          hardLimitBytes: 2147483648,
        );
      }

      throw Exception('Compression cancelled by user');
    }

    if (exitCode != 0) {
      final errorContext = recentStderr.join('\n').trim();
      throw Exception('FFmpeg failed with exit code $exitCode ($encoder):\n$errorContext');
    }

    // Verify output file exists and has size
    final outFile = File(outputPath);
    if (!await outFile.exists() || await outFile.length() == 0) {
      throw Exception('Output video file was not generated or is empty');
    }

    return outputPath;
  }

  /// Generates a lightweight 1080p editing proxy alongside the archive with resilient fallback
  Future<String> generateProxyVideo({
    required VideoTask task,
    String? customProxyPath,
  }) async {
    _isCancelled = false;

    final proxyPath = _resolveProxyPath(task, customProxyPath);
    final preferredEncoder = await getAvailableProxyEncoder();

    try {
      return await _executeProxyGeneration(
        task: task,
        proxyPath: proxyPath,
        proxyEncoder: preferredEncoder,
      );
    } catch (e) {
      if (_isCancelled) rethrow;

      if (preferredEncoder != 'libx264') {
        debugPrint('Proxy encoder ($preferredEncoder) failed: $e. Retrying with libx264...');
        final partial = File(proxyPath);
        if (await partial.exists()) {
          try { await partial.delete(); } catch (_) {}
        }
        return await _executeProxyGeneration(
          task: task,
          proxyPath: proxyPath,
          proxyEncoder: 'libx264',
        );
      }
      rethrow;
    }
  }

  Future<String> _executeProxyGeneration({
    required VideoTask task,
    required String proxyPath,
    required String proxyEncoder,
  }) async {
    final oldFile = File(proxyPath);
    if (await oldFile.exists()) {
      await oldFile.delete();
    }

    final ffmpeg = resolveExecutable('ffmpeg');

    final List<String> args = [
      '-y',
      '-i', task.inputPath,
      '-vf', 'scale=-2:1080',
      '-map', '0:v:0',
      '-map', '0:a?',
      '-map_metadata', '0',
    ];

    if (proxyEncoder == 'h264_videotoolbox') {
      args.addAll(['-c:v', 'h264_videotoolbox', '-pix_fmt', 'yuv420p', '-b:v', '2500k']);
    } else if (proxyEncoder == 'h264_nvenc') {
      args.addAll(['-c:v', 'h264_nvenc', '-pix_fmt', 'yuv420p', '-b:v', '2500k', '-preset', 'p4']);
    } else if (proxyEncoder == 'h264_qsv') {
      args.addAll(['-c:v', 'h264_qsv', '-pix_fmt', 'nv12', '-b:v', '2500k']);
    } else if (proxyEncoder == 'h264_amf') {
      args.addAll(['-c:v', 'h264_amf', '-pix_fmt', 'nv12', '-b:v', '2500k']);
    } else {
      args.addAll(['-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-preset', 'veryfast', '-b:v', '2500k']);
    }

    args.addAll([
      '-c:a', 'aac',
      '-b:a', '128k',
      '-movflags', '+faststart',
      proxyPath,
    ]);

    debugPrint('Generating Proxy ($proxyEncoder): $ffmpeg ${args.join(' ')}');
    final process = await Process.start(ffmpeg, args);
    _activeProcess = process;

    final List<String> recentStderr = [];
    process.stderr.transform(utf8.decoder).listen((line) {
      if (_isCancelled) return;
      recentStderr.add(line);
      if (recentStderr.length > 20) recentStderr.removeAt(0);
    });

    final exitCode = await process.exitCode;
    _activeProcess = null;

    if (exitCode != 0 || !await File(proxyPath).exists()) {
      final err = recentStderr.join('\n').trim();
      throw Exception('Failed to generate 1080p proxy file ($proxyEncoder):\n$err');
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
