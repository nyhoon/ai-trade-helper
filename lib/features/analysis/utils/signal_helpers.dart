import '../../../core/data/app_data_manager.dart';

class SignalHelpers {
  static Future<void> saveOpportunitySignal({
    required String stockCode,
    required String stockName,
    required String signalType,
    required double currentPrice,
    required String styleName,
  }) async {
    final signalRepo = AppDataManager.instance.signalHistoryRepository;
    await signalRepo.saveSignal(
      stockCode: stockCode,
      signalType: signalType,
      signalStrength: 0.8,
      price: currentPrice,
      volume: 0.0,
      confidence: 0.8,
      memo: 'Opportunity_$styleName',
    );

    final notificationRepo = AppDataManager.instance.notificationHistoryRepository;
    await notificationRepo.saveNotification(
      type: 'opportunity',
      stockCode: stockCode,
      stockName: stockName,
      message: '$stockCode: $signalType 발견 (${currentPrice.toStringAsFixed(0)}원)',
    );
  }
}


