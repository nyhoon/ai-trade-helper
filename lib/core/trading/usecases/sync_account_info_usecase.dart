import '../../data/app_data_manager.dart';
import '../../database/repositories/holdings_repository.dart';
import '../../api/kis_unified_api_service.dart';

class SyncAccountInfoUseCase {
  final HoldingsRepository _holdingsRepository = HoldingsRepository();

  Future<void> execute() async {
    // 1) 로컬 DB에서 기존 계좌/보유 읽기 (필요 시)
    // 2) API로 최신 계좌/보유 업데이트 → DB 반영
    final positions = await KisUnifiedApiService().getPositionsCompat();
    await _holdingsRepository.syncWithApi(positions);
  }
}


