import 'package:ai_helper/core/data/app_data_manager.dart';
import 'package:intl/intl.dart';

/// 통합 주식 유틸리티 클래스
class StockUtils {
  StockUtils._();
  static final StockUtils instance = StockUtils._();

  /// 통합 종목 구분: 해외주식 vs 국내주식
  bool isOverseasStock(String symbol) {
    if (symbol.isEmpty) return false;
    
    final String code = symbol.trim().toUpperCase();
    
    // 1. 데이터베이스 market 필드 우선 확인
    try {
      final stockInfo = AppDataManager.instance.getStockInfo(symbol);
      final String? market = stockInfo?['market'] as String?;
      if (market != null) {
        final marketUpper = market.toUpperCase();
        final bool isUsMarket = marketUpper == 'NASDAQ' ||
            marketUpper == 'NASD' ||
            marketUpper == 'NYSE' ||
            marketUpper == 'AMEX' ||
            marketUpper == 'US' ||
            marketUpper == 'USA';
        
        if (isUsMarket) {
          print('🔍 [StockUtils] 데이터베이스 market 필드: $symbol → $market (해외)');
          return true;
        }
      }
    } catch (e) {
      print('⚠️ [StockUtils] 데이터베이스 market 확인 실패: $e');
    }

    // 2. 기존 KIS API 패턴 기반 판별 (getStockPriceAuto 로직 반영)
    // - 해외주식: 대문자 영문 1-5자리 (예: AAPL, TSLA, NVD)
    // - 국내주식: 6자리 숫자 (예: 005930, 001060)
    final bool isOverseasPattern = RegExp(r'^[A-Z]{1,5}$').hasMatch(code);
    final bool isDomesticPattern = RegExp(r'^[0-9]{6}$').hasMatch(code);
    
    if (isOverseasPattern) {
      print('🔍 [StockUtils] KIS API 패턴: $symbol → 해외주식 (영문 1-5자리)');
      return true;
    } else if (isDomesticPattern) {
      print('🔍 [StockUtils] KIS API 패턴: $symbol → 국내주식 (6자리 숫자)');
      return false;
    }

    // 3. 확장 패턴 (ETF, 특수 종목)
    // - 해외 ETF: 영문 + 숫자/점 포함 (예: BRK.B, PLTZ)
    // - 해외 특수: 알파벳 포함하고 숫자만은 아님
    final bool isOverseasETF = RegExp(r'^[A-Z\.]{1,10}$').hasMatch(code) ||
        (RegExp(r'[A-Z]').hasMatch(code) && !RegExp(r'^\d+$').hasMatch(code));
    
    if (isOverseasETF) {
      print('🔍 [StockUtils] 확장 패턴: $symbol → 해외주식 (ETF/특수)');
      return true;
    }

    // 4. 기본값: 알파벳 포함이면 해외, 숫자만이면 국내
    final bool hasAlphabet = RegExp(r'[A-Z]').hasMatch(code);
    final bool isAllNumbers = RegExp(r'^\d+$').hasMatch(code);
    
    if (hasAlphabet && !isAllNumbers) {
      print('🔍 [StockUtils] 기본 휴리스틱: $symbol → 해외주식 (알파벳 포함)');
      return true;
    } else if (isAllNumbers) {
      print('🔍 [StockUtils] 기본 휴리스틱: $symbol → 국내주식 (숫자만)');
      return false;
    }

    print('🔍 [StockUtils] 기본 휴리스틱: $symbol → 국내주식 (기본값)');
    return false;
  }

  /// 통합 종목 시장 구분: 'DOMESTIC' | 'OVERSEAS'
  String getStockMarket(String symbol) {
    return isOverseasStock(symbol) ? 'OVERSEAS' : 'DOMESTIC';
  }

  /// 국내주식인지 확인
  bool isDomesticStock(String symbol) {
    return !isOverseasStock(symbol);
  }

  /// 통합 가격 포맷팅: 해외($) vs 국내(원)
  String formatPrice(double price, String symbol) {
    final bool isOverseas = isOverseasStock(symbol);
    
    if (isOverseas) {
      return '\$${price.toStringAsFixed(2)}';
    } else {
      return '${NumberFormat('#,###').format(price)}원';
    }
  }

  /// 통합 가격 포맷팅 (숫자만): 해외($) vs 국내(원)
  String formatPricePlain(double price, String symbol) {
    final bool isOverseas = isOverseasStock(symbol);
    
    if (isOverseas) {
      return '\$${price.toStringAsFixed(2)}';
    } else {
      return NumberFormat('#,###').format(price);
    }
  }

  /// 통합 거래량 포맷팅
  String formatVolume(int volume) {
    return NumberFormat('#,###').format(volume);
  }

  /// 통합 등락률 포맷팅
  String formatChangeRate(double rate) {
    final sign = rate >= 0 ? '+' : '';
    return '$sign${rate.toStringAsFixed(2)}%';
  }

  /// 통합 등락금액 포맷팅
  String formatChangeAmount(double amount, String symbol) {
    final bool isOverseas = isOverseasStock(symbol);
    final sign = amount >= 0 ? '+' : '';
    
    if (isOverseas) {
      return '$sign\$${amount.toStringAsFixed(2)}';
    } else {
      return '$sign${NumberFormat('#,###').format(amount)}';
    }
  }
}