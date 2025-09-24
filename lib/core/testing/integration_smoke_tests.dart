import 'dart:developer' as developer;
import 'package:cloud_functions/cloud_functions.dart';

class IntegrationSmokeTests {
  static Future<void> runOnce() async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast3');
      final callable = functions.httpsCallable('analyzeStock');
      final res = await callable.call({
        'symbol': 'AAPL',
        'days': 100,
        'buyThreshold': 0.6,
        'sellThreshold': -0.6,
      });
      developer.log('server analysis => ${res.data}', name: 'SmokeTest');
    } catch (e, st) {
      developer.log('server analysis failed: $e', name: 'SmokeTest', error: e, stackTrace: st);
    }
  }
}
