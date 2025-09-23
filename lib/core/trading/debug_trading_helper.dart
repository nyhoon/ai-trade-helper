import 'investment_style_manager.dart';
import '../data/app_data_manager.dart';

/// 매수 문제 디버깅을 위한 헬퍼 클래스
class DebugTradingHelper {
  static final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  static final AppDataManager _appDataManager = AppDataManager.instance;

  /// 현재 투자 스타일 설정 상태 확인
  static Future<void> checkCurrentStyleSettings() async {
    try {
      print('🔍 === 투자 스타일 설정 상태 확인 ===');
      
      // 현재 스타일 확인
      final currentStyle = _styleManager.currentStyle;
      print('📊 현재 투자 스타일: ${currentStyle.name}');
      
      // 스타일 파라미터 로드
      final styleParams = await _styleManager.getStyleParameters(currentStyle);
      print('📋 스타일 파라미터:');
      print('   - 매수 임계값: ${styleParams['buyThreshold']}');
      print('   - 매도 임계값: ${styleParams['sellThreshold']}');
      print('   - 투자 비율: ${(styleParams['positionSize'] * 100).toStringAsFixed(1)}%');
      print('   - 최대 종목 수: ${styleParams['maxStocks']}개');
      print('   - 부분익절: ${styleParams['partialProfit']}%');
      print('   - 전체익절: ${styleParams['fullProfit']}%');
      print('   - 손절: ${styleParams['stopLoss']}%');
      print('   - 일일손실한도: ${styleParams['dailyLossLimit']}%');
      
      // 계좌 정보 확인
      final accountInfo = await _appDataManager.getAccountBalance();
      if (accountInfo != null) {
        print('💰 계좌 정보:');
        print('   - 주문가능금액: ${accountInfo['availableBalance']}원');
        print('   - 총 자산: ${accountInfo['totalBalance']}원');
      } else {
        print('❌ 계좌 정보 조회 실패');
      }
      
      // 보유종목 확인
      final holdings = await _appDataManager.getHoldingsFromDatabase();
      print('📦 보유종목: ${holdings.length}개');
      for (final holding in holdings) {
        print('   - ${holding['stock_code']}: ${holding['quantity']}주');
      }
      
      print('✅ === 설정 상태 확인 완료 ===');
      
    } catch (e) {
      print('❌ 설정 상태 확인 실패: $e');
    }
  }

  /// 매수 시그널 테스트
  static Future<void> testBuySignal(String stockCode, double comprehensiveScore) async {
    try {
      print('🧪 === 매수 시그널 테스트 ===');
      print('📊 테스트 종목: $stockCode');
      print('📊 종합점수: ${comprehensiveScore.toStringAsFixed(3)}');
      
      // 현재 스타일 설정 가져오기
      final currentStyle = _styleManager.currentStyle;
      final styleParams = await _styleManager.getStyleParameters(currentStyle);
      final buyThreshold = (styleParams['buyThreshold'] as num?)?.toDouble();
      final sellThreshold = (styleParams['sellThreshold'] as num?)?.toDouble();
      
      print('📋 임계값 확인:');
      print('   - 매수 임계값: $buyThreshold');
      print('   - 매도 임계값: $sellThreshold');
      
      if (buyThreshold == null || sellThreshold == null) {
        print('❌ 임계값이 설정되지 않았습니다.');
        return;
      }
      
      // 시그널 결정
      String signal = '관망';
      if (comprehensiveScore >= buyThreshold) {
        signal = '매수';
        print('✅ 매수 시그널 조건 충족!');
      } else if (comprehensiveScore <= sellThreshold) {
        signal = '매도';
        print('✅ 매도 시그널 조건 충족!');
      } else {
        // 임계값 사이 구간: 관망
        signal = '관망';
        print('➖ 관망 상태 (임계값 사이 구간: ${sellThreshold.toStringAsFixed(3)} < 점수 < ${buyThreshold.toStringAsFixed(3)})');
      }
      
      print('🎯 최종 시그널: $signal');
      print('✅ === 매수 시그널 테스트 완료 ===');
      
    } catch (e) {
      print('❌ 매수 시그널 테스트 실패: $e');
    }
  }

  /// 매수 조건 검증
  static Future<void> validateBuyConditions(String stockCode) async {
    try {
      print('🔍 === 매수 조건 검증 ===');
      print('📊 검증 종목: $stockCode');
      
      // 1. 보유종목 확인
      final holdings = await _appDataManager.getHoldingsFromDatabase();
      final existingHolding = holdings.firstWhere(
        (h) => h['stock_code'] == stockCode || h['stockCode'] == stockCode,
        orElse: () => <String, dynamic>{},
      );
      
      print('📦 보유종목 확인:');
      if (existingHolding.isNotEmpty) {
        print('   - 이미 보유 중: ${existingHolding['quantity']}주');
      } else {
        print('   - 신규 종목');
      }
      
      // 2. 최대 종목 수 확인
      final currentStyle = _styleManager.currentStyle;
      final styleParams = await _styleManager.getStyleParameters(currentStyle);
      final maxStocks = (styleParams['maxStocks'] as num?)?.toInt();
      
      print('📊 최대 종목 수 확인:');
      print('   - 현재 보유: ${holdings.length}개');
      print('   - 최대 허용: $maxStocks개');
      print('   - 상태: ${holdings.length >= (maxStocks ?? 0) ? '초과' : '허용'}');
      
      // 3. 계좌 잔고 확인
      final accountInfo = await _appDataManager.getAccountBalance();
      if (accountInfo != null) {
        final availableAmount = (accountInfo['availableBalance'] as num?)?.toDouble() ?? 0.0;
        final positionSize = (styleParams['positionSize'] as num?)?.toDouble() ?? 0.0;
        final orderAmount = availableAmount * positionSize;
        
        print('💰 계좌 잔고 확인:');
        print('   - 주문가능금액: ${availableAmount.toStringAsFixed(0)}원');
        print('   - 투자 비율: ${(positionSize * 100).toStringAsFixed(1)}%');
        print('   - 계산된 주문금액: ${orderAmount.toStringAsFixed(0)}원');
        print('   - 상태: ${availableAmount > 0 ? '충분' : '부족'}');
      }
      
      print('✅ === 매수 조건 검증 완료 ===');
      
    } catch (e) {
      print('❌ 매수 조건 검증 실패: $e');
    }
  }
}
