import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

/// Host side of integration_test/perf_test.dart: turns the recorded timeline
/// into `build/perf/<key>.timeline_summary.json`.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    for (final entry in data.entries) {
      final timeline = driver.Timeline.fromJson(
        entry.value as Map<String, dynamic>,
      );
      await driver.TimelineSummary.summarize(timeline).writeTimelineToFile(
        entry.key,
        destinationDirectory: 'build/perf',
        pretty: true,
        includeSummary: true,
      );
    }
  },
);
