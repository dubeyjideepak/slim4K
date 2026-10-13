import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slim4k/models/app_activation.dart';
import 'package:slim4k/models/video_task.dart';
import 'package:slim4k/services/compression_engine.dart';
import 'package:slim4k/widgets/activation_lock_widget.dart';

void main() {
  test('ClientActivation model & 15-day expiry calculations', () {
    final now = DateTime.now();
    final activation = ClientActivation(
      appId: 'slim4k',
      clientId: 'c_macos_test123',
      platform: 'macos',
      isActive: true, // true by default
      lastHeartbeat: now.subtract(const Duration(days: 3)),
      firstRegisteredAt: now.subtract(const Duration(days: 10)),
    );

    expect(activation.appId, 'slim4k');
    expect(activation.clientId, 'c_macos_test123');
    expect(activation.platform, 'macos');
    expect(activation.isActive, isTrue);
    expect(activation.daysSinceLastHeartbeat, 3);
    expect(activation.daysRemainingBeforeExpiry, 12);

    // Test 16-day disconnected client
    final expiredActivation = ClientActivation(
      appId: 'slim4k',
      clientId: 'c_macos_expired',
      platform: 'macos',
      isActive: true,
      lastHeartbeat: now.subtract(const Duration(days: 16)),
      firstRegisteredAt: now.subtract(const Duration(days: 30)),
    );
    expect(expiredActivation.daysSinceLastHeartbeat, 16);
    expect(expiredActivation.daysRemainingBeforeExpiry, 0);
  });

  testWidgets('ActivationLockWidget renders locked state properly', (WidgetTester tester) async {
    final activation = ClientActivation(
      appId: 'slim4k',
      clientId: 'c_test_device_99',
      platform: 'macos',
      isActive: false,
      lastHeartbeat: DateTime.now().subtract(const Duration(days: 16)),
      firstRegisteredAt: DateTime.now().subtract(const Duration(days: 20)),
      status: ActivationStatus.deactivatedExpired,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ActivationLockWidget(
          activation: activation,
          onReactivated: () {},
        ),
      ),
    );

    expect(find.text('15-Day Offline Limit Exceeded'), findsOneWidget);
    expect(find.text('c_test_device_99'), findsOneWidget);
    expect(find.text('slim4k'), findsOneWidget);
    expect(find.text('Check Status & Re-activate'), findsOneWidget);
  });

  test('VideoTask size formatting and ROI calculations', () {
    final task = VideoTask(
      id: 'test_1',
      inputPath: '/test/video.mp4',
      fileName: 'video.mp4',
      inputFileSize: 100 * 1024 * 1024, // 100 MB
      outputFileSize: 10 * 1024 * 1024,  // 10 MB
      generateProxy: true,
      proxyFileSize: 2 * 1024 * 1024,    // 2 MB
    );

    expect(task.formattedInputSize, '100.00 MB');
    expect(task.formattedOutputSize, '10.00 MB');
    expect(task.formattedProxySize, '2.00 MB');
    expect(task.spaceSavedPercentage, closeTo(90.0, 0.1));
    expect(task.reductionFactor, closeTo(10.0, 0.1));
  });

  test('CompressionEngine videoExtensions coverage', () {
    expect(CompressionEngine.videoExtensions.contains('.mp4'), isTrue);
    expect(CompressionEngine.videoExtensions.contains('.mov'), isTrue);
    expect(CompressionEngine.videoExtensions.contains('.mkv'), isTrue);
    expect(CompressionEngine.videoExtensions.contains('.mts'), isTrue);
    expect(CompressionEngine.videoExtensions.contains('.pdf'), isFalse);
    expect(CompressionEngine.videoExtensions.contains('.wav'), isFalse);
  });
}
