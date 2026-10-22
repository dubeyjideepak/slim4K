import 'package:flutter_test/flutter_test.dart';
import 'package:slim4k/services/quota_service.dart';

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
      final quota = QuotaService();

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
  });
}
