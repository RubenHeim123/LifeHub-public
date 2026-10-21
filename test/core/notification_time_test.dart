import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/services/notification_service.dart';

void main() {
  test('the daily reminder fires today if the time is still ahead, otherwise tomorrow – in local time', () {
    final noon = DateTime(2026, 10, 11, 13, 46);
    expect(NotificationService.nextDaily(noon, 21, 0), DateTime(2026, 10, 11, 21, 0));
    expect(NotificationService.nextDaily(noon, 7, 30), DateTime(2026, 10, 12, 7, 30));
    expect(NotificationService.nextDaily(DateTime(2026, 10, 11, 21, 0), 21, 0), DateTime(2026, 10, 12, 21, 0)); // genau jetzt → morgen
    // über die Zeitumstellung (25.10.2026) bleibt es 21:00 Ortszeit
    expect(NotificationService.nextDaily(DateTime(2026, 10, 24, 22, 0), 21, 0), DateTime(2026, 10, 25, 21, 0));
  });
}
