import '../../data/app_data_manager.dart';
import '../../database/repositories/holdings_repository.dart';
import '../../api/kis_unified_api_service.dart';

class SyncUniverseUseCase {
  final HoldingsRepository _holdingsRepository = HoldingsRepository();

  Future<void> execute() async {
    // 관심종목은 AppDataManager가 내부적으로 관리/DB 저장
    await AppDataManager.instance.getWatchlist();
    // 보유는 최신 API 동기화 이미 포함됨 (SyncAccountInfo 이후 보완용)
    final overseas = await KisUnifiedApiService().getOverseasPresentBalanceCompat();
    if (overseas.isNotEmpty) {
      await _holdingsRepository.syncWithApi(overseas);
    }
  }
}


