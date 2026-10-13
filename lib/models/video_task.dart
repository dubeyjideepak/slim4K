enum CompressionPreset {
  slim10x,
  ultra15x,
  extreme20x,
  custom,
}

enum TaskStatus {
  idle,
  analyzing,
  compressing,
  completed,
  error,
  cancelled,
}

class VideoTask {
  final String id;
  final String inputPath;
  final String fileName;
  final int inputFileSize;
  int durationMs;
  int width;
  int height;
  double fps;
  int originalBitrateKbps;

  CompressionPreset preset;
  int targetBitrateKbps;
  TaskStatus status;
  double progress;
  double currentFps;
  double speedMultiplier;
  Duration? estimatedTimeRemaining;
  String? outputPath;
  int? outputFileSize;
  String? errorMessage;

  // Professional Cameraman Workflow Features
  bool generateProxy;
  String? proxyPath;
  int? proxyFileSize;
  bool preserveOriginalAudio;
  bool isVerified;
  bool isOriginalTrashed;
  String? relativeSubPath;

  VideoTask({
    required this.id,
    required this.inputPath,
    required this.fileName,
    required this.inputFileSize,
    this.durationMs = 0,
    this.width = 3840,
    this.height = 2160,
    this.fps = 30.0,
    this.originalBitrateKbps = 100000,
    this.preset = CompressionPreset.slim10x,
    this.targetBitrateKbps = 10000,
    this.status = TaskStatus.idle,
    this.progress = 0.0,
    this.currentFps = 0.0,
    this.speedMultiplier = 1.0,
    this.estimatedTimeRemaining,
    this.outputPath,
    this.outputFileSize,
    this.errorMessage,
    this.generateProxy = false,
    this.proxyPath,
    this.proxyFileSize,
    this.preserveOriginalAudio = true,
    this.isVerified = false,
    this.isOriginalTrashed = false,
    this.relativeSubPath,
  });

  String get formattedInputSize => formatBytes(inputFileSize);

  String get formattedOutputSize =>
      outputFileSize != null ? formatBytes(outputFileSize!) : 'N/A';

  String get formattedProxySize =>
      proxyFileSize != null ? formatBytes(proxyFileSize!) : 'N/A';

  String get formattedEstimatedSize {
    if (durationMs > 0) {
      final estimatedBytes = ((targetBitrateKbps * 1000) / 8) * (durationMs / 1000);
      return formatBytes(estimatedBytes.round());
    }
    // Default estimated 1/10th
    return formatBytes((inputFileSize * 0.1).round());
  }

  double get spaceSavedPercentage {
    if (outputFileSize == null || inputFileSize == 0) return 0.0;
    final saved = (inputFileSize - outputFileSize!) / inputFileSize * 100;
    return saved.clamp(0.0, 100.0);
  }

  double get reductionFactor {
    if (outputFileSize == null || outputFileSize == 0) return 1.0;
    return inputFileSize / outputFileSize!;
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(i > 1 ? 2 : 0)} ${suffixes[i]}';
  }
}
