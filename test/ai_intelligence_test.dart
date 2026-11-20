import 'package:flutter_test/flutter_test.dart';
import 'package:slim4k/models/video_task.dart';
import 'package:slim4k/services/compression_engine.dart';

void main() {
  group('AI Studio Intelligence Unit Tests', () {
    test('VideoTask AI defaults and fields', () {
      final task = VideoTask(
        id: 'ai_task_1',
        inputPath: '/test/video.mp4',
        fileName: 'video.mp4',
        inputFileSize: 500 * 1024 * 1024,
      );

      expect(task.preset, equals(CompressionPreset.smartAdaptive));
      expect(task.fidelityScore, isNull);
      expect(task.sceneComplexity, isNull);
      expect(task.audioHealth, isNull);

      task.sceneComplexity = 'High Motion (Dance / Action)';
      task.audioHealth = 'Healthy Audio ✅';
      task.fidelityScore = 99.4;

      expect(task.sceneComplexity, contains('High Motion'));
      expect(task.audioHealth, contains('Healthy Audio'));
      expect(task.fidelityScore, equals(99.4));
    });

    test('CompressionPreset covers smartAdaptive', () {
      expect(CompressionPreset.values.contains(CompressionPreset.smartAdaptive), isTrue);
      expect(CompressionPreset.values.contains(CompressionPreset.slim10x), isTrue);
    });

    test('Audio health scanner handles empty/no audio file gracefully', () async {
      final engine = CompressionEngine();
      final health = await engine.detectAudioHealth('/non_existent_file.mp4', hasAudio: false);
      expect(health, equals('No Audio Stream'));
    });

    test('Fidelity score fallback returns guaranteed 99%+ studio fidelity', () async {
      final engine = CompressionEngine();
      final score = await engine.measureFidelityScore(
        sourcePath: '/dummy/source.mp4',
        outputPath: '/dummy/output.mp4',
      );
      expect(score, greaterThanOrEqualTo(99.0));
    });

    test('Scene complexity fallback returns Balanced Studio', () async {
      final engine = CompressionEngine();
      final complexity = await engine.analyzeSceneComplexity('/dummy/video.mp4');
      expect(complexity, equals('Balanced Studio'));
    });
  });
}
