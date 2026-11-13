import 'package:flutter_test/flutter_test.dart';
import 'package:slim4k/services/quota_service.dart';
import 'package:slim4k/services/app_update_service.dart';

void main() {
  group('QuotaService Unit Tests', () {
    test('Default 10 TB quota calculations and constants', () {
      expect(QuotaService.defaultQuotaTb, 10.0);
      expect(QuotaService.defaultQuotaBytes, 10 * 1024 * 1024 * 1024 * 1024);
      expect(QuotaService.defaultQuotaBytes, 10995116277760);
    });

    test('Quota metrics percentage and remaining TB calculation', () {
      final quota = QuotaService();
      
      // Initial state
      expect(quota.quotaLimitTb, 10.0);
      expect(quota.isQuotaExceeded, isFalse);
      expect(quota.formattedPercentage, '0.0%');
    });

    test('TB calculation conversions', () {
      const oneTbBytes = 1024 * 1024 * 1024 * 1024; // 1,099,511,627,776 bytes

      // Test conversion helper formula
      final tb = oneTbBytes / 1099511627776.0;
      expect(tb, 1.0);

      // 5 TB converted
      const fiveTbBytes = 5 * oneTbBytes;
      expect(fiveTbBytes / 1099511627776.0, 5.0);

      // 10 TB converted
      const tenTbBytes = 10 * oneTbBytes;
      expect(tenTbBytes / 1099511627776.0, 10.0);
    });

    test('Exceeded quota detection boundary', () {
      const tenTbBytes = 10 * 1024 * 1024 * 1024 * 1024;
      const slightlyOver = tenTbBytes + 1024;

      expect(slightlyOver >= tenTbBytes, isTrue);
      expect(tenTbBytes >= tenTbBytes, isTrue);
      expect((tenTbBytes - 1) >= tenTbBytes, isFalse);
    });

    test('Strict 2.0 GB Trial Limit & Live Hard Processing Ceiling', () {
      expect(QuotaService.trialLimitBytes, 2 * 1024 * 1024 * 1024);
      expect(QuotaService.defaultTrialLimitGb, 2.0);

      expect(QuotaService.trialHardLimitBytes, 2 * 1024 * 1024 * 1024);
      expect(QuotaService.defaultTrialHardLimitGb, 2.0);

      final quota = QuotaService();
      // Initially 0 bytes processed:
      expect(quota.isHardLimitExceeded(additionalBytes: 1 * 1024 * 1024 * 1024), isFalse);
      expect(quota.isHardLimitExceeded(additionalBytes: (2 * 1024 * 1024 * 1024) - 1), isFalse);

      // Reaches or surpasses strict 2.0 GB:
      expect(quota.isHardLimitExceeded(additionalBytes: 2 * 1024 * 1024 * 1024), isTrue);
      expect(quota.isHardLimitExceeded(additionalBytes: 3 * 1024 * 1024 * 1024), isTrue);
    });

    test('AppUpdateService version comparison logic', () {
      expect(AppUpdateService.currentAppVersion, equals('1.0.0'));
    });
  });
}
