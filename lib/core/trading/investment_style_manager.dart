import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'investment_style.dart';
import '../database/repositories/investment_style_repository.dart';

class InvestmentStyleManager {
  static final InvestmentStyleManager _instance = InvestmentStyleManager._internal();
  factory InvestmentStyleManager() => _instance;
  InvestmentStyleManager._internal();

  // Repository
  final InvestmentStyleRepository _repository = InvestmentStyleRepository();

  // 현재 투자 스타일
  InvestmentStyle _currentStyle = InvestmentStyle.moderate;
  
  // 커스터마이징 모드 (AI 최적화 vs 사용자 커스터마이징)
  bool _isCustomMode = false;
  
  // 현재 스타일의 상세 설정
  Map<String, dynamic>? _currentStyleSettings;
  
  // 스타일 변경 리스너
  final StreamController<InvestmentStyle> _styleController = StreamController<InvestmentStyle>.broadcast();
  
  // 커스터마이징 모드 변경 리스너
  final StreamController<bool> _customModeController = StreamController<bool>.broadcast();
  
  // 스타일 설정 변경 리스너
  final StreamController<Map<String, dynamic>> _styleSettingsController = StreamController<Map<String, dynamic>>.broadcast();

  // Getters
  InvestmentStyle get currentStyle => _currentStyle;
  bool get isCustomMode => _isCustomMode;
  Map<String, dynamic>? get currentStyleSettings => _currentStyleSettings;
  Stream<InvestmentStyle> get styleStream => _styleController.stream;
  Stream<bool> get customModeStream => _customModeController.stream;
  Stream<Map<String, dynamic>> get styleSettingsStream => _styleSettingsController.stream;

  // 초기화
  Future<void> initialize() async {
    await _loadCurrentStyle();
    await _loadCustomMode();
    await _loadCurrentStyleSettings();
  }

  // 현재 스타일 로드
  Future<void> _loadCurrentStyle() async {
    final prefs = await SharedPreferences.getInstance();
    final styleIndex = prefs.getInt('current_investment_style') ?? 1; // 기본값: 일반적
    _currentStyle = InvestmentStyle.values[styleIndex];
    _styleController.add(_currentStyle);
  }

  // 커스터마이징 모드 로드
  Future<void> _loadCustomMode() async {
    final prefs = await SharedPreferences.getInstance();
    _isCustomMode = prefs.getBool('is_custom_mode') ?? false; // 기본값: AI 최적화 모드
    _customModeController.add(_isCustomMode);
  }

  // 현재 스타일 설정 로드
  Future<void> _loadCurrentStyleSettings() async {
    try {
      final styleName = getStyleName();
      _currentStyleSettings = await _repository.getInvestmentStyle(styleName);
      
      if (_currentStyleSettings == null) {
        print('⚠️ 데이터베이스에 스타일 설정이 없습니다. 기본값을 사용합니다.');
        _currentStyleSettings = _getDefaultStyleSettings();
      }
      
      _styleSettingsController.add(_currentStyleSettings!);
      print('📊 스타일 설정 로드 완료: $styleName');
    } catch (e) {
      print('❌ 스타일 설정 로드 실패: $e');
      _currentStyleSettings = _getDefaultStyleSettings();
    }
  }

  // 기본 스타일 설정 반환
  Map<String, dynamic> _getDefaultStyleSettings() {
    switch (_currentStyle) {
      case InvestmentStyle.conservative:
        return {
          'style_name': '안정적 투자',
          'rsi_condition': 35.0,
          'volume_condition': 1.2,  // 120% (기존 1.8에서 수정)
          'target_return_min': 15.0,
          'target_return_max': 25.0,
          'max_loss_min': 3.0,
          'max_loss_max': 5.0,
        };
      case InvestmentStyle.moderate:
        return {
          'style_name': '일반적 투자',
          'rsi_condition': 30.0,
          'volume_condition': 1.0,  // 100% (기존 1.5에서 수정)
          'target_return_min': 25.0,
          'target_return_max': 40.0,
          'max_loss_min': 5.0,
          'max_loss_max': 8.0,
        };
      case InvestmentStyle.aggressive:
        return {
          'style_name': '공격적 투자',
          'rsi_condition': 45.0, // 공격적 투자: RSI 45 이하에서 매수
          'volume_condition': 0.8,  // 80% (기존 1.2에서 수정)
          'target_return_min': 40.0,
          'target_return_max': 60.0,
          'max_loss_min': 8.0,
          'max_loss_max': 12.0,
        };
    }
  }



  // 스타일 변경
  Future<void> setStyle(InvestmentStyle style) async {
    _currentStyle = style;
    _styleController.add(_currentStyle);
    
    // SharedPreferences에 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('current_investment_style', style.index);
    
    // 새로운 스타일 설정 로드
    await _loadCurrentStyleSettings();
    
    print('🔄 투자 스타일 변경: ${getStyleName()}');
  }

  // 커스터마이징 모드 변경
  Future<void> setCustomMode(bool isCustom) async {
    _isCustomMode = isCustom;
    _customModeController.add(_isCustomMode);
    
    // SharedPreferences에 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_custom_mode', isCustom);
  }

  // 커스터마이징 모드 조회
  Future<bool> getCustomMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_custom_mode') ?? false;
  }

  // 특정 스타일의 파라미터 반환 (백테스팅용)
  Future<Map<String, dynamic>> getStyleParameters(InvestmentStyle style) async {
    try {
      final styleName = _getStyleName(style);
      
      // 데이터베이스에서 스타일 설정 조회
      final styleSettings = await _repository.getInvestmentStyle(styleName);
      
      print('🔍 스타일 파라미터 로드 ($styleName):');
      print('   - DB buy_threshold: ${styleSettings?['buy_threshold']}');
      print('   - DB sell_threshold: ${styleSettings?['sell_threshold']}');
      print('   - DB partial_profit: ${styleSettings?['partial_profit']}');
      print('   - DB full_profit: ${styleSettings?['full_profit']}');
      print('   - DB stop_loss: ${styleSettings?['stop_loss']}');
      print('   - DB position_size: ${styleSettings?['position_size']}');
      print('   - DB max_stocks: ${styleSettings?['max_stocks']}');
      print('   - DB daily_loss_limit: ${styleSettings?['daily_loss_limit']}');
      
      // 스타일 설정이 없으면 기본값 초기화 후 반환
      if (styleSettings == null) {
        print('❌ $styleName 스타일 설정이 없습니다. 기본값을 초기화합니다.');
        await _repository.initializeDefaultStyles();
        final newStyleSettings = await _repository.getInvestmentStyle(styleName);
        if (newStyleSettings != null) {
          // 데이터베이스에서 로드한 값으로 변환
          return {
            'partialProfit': (newStyleSettings['partial_profit'] as num?)?.toDouble() ?? 0.0,
            'fullProfit': (newStyleSettings['full_profit'] as num?)?.toDouble() ?? 0.0,
            'stopLoss': (newStyleSettings['stop_loss'] as num?)?.toDouble() ?? 0.0,
            'positionSize': (newStyleSettings['position_size'] as num?)?.toDouble() ?? 0.0,
            'maxStocks': (newStyleSettings['max_stocks'] as num?)?.toInt() ?? 0,
            'dailyLossLimit': (newStyleSettings['daily_loss_limit'] as num?)?.toDouble() ?? 0.0,
            'buyThreshold': (newStyleSettings['buy_threshold'] as num?)?.toDouble() ?? 0.0,
            'sellThreshold': (newStyleSettings['sell_threshold'] as num?)?.toDouble() ?? 0.0,
          };
        }
        return _getDefaultStyleSettingsForStyle(style);
      }
      
      // 사용자가 설정한 값만 사용 (기본값 없이)
      final partialProfit = (styleSettings['partial_profit'] as num?)?.toDouble() ?? 0.0;
      final fullProfit = (styleSettings['full_profit'] as num?)?.toDouble() ?? 0.0;
      final stopLoss = (styleSettings['stop_loss'] as num?)?.toDouble() ?? 0.0;
      final positionSize = (styleSettings['position_size'] as num?)?.toDouble() ?? 0.0;
      final maxStocks = (styleSettings['max_stocks'] as num?)?.toInt() ?? 0;
      final dailyLossLimit = (styleSettings['daily_loss_limit'] as num?)?.toDouble() ?? 0.0;
      final buyThreshold = (styleSettings['buy_threshold'] as num?)?.toDouble() ?? 0.0;
      final sellThreshold = (styleSettings['sell_threshold'] as num?)?.toDouble() ?? 0.0;
      
      // 매수/매도 임계값이 0이거나 null인 경우 기본값으로 강제 설정
      final defaultSettings = _getDefaultStyleSettingsForStyle(style);
      final finalBuyThreshold = (buyThreshold == 0.0 || buyThreshold == null) 
          ? defaultSettings['buyThreshold'] as double 
          : buyThreshold;
      final finalSellThreshold = (sellThreshold == 0.0 || sellThreshold == null) 
          ? defaultSettings['sellThreshold'] as double 
          : sellThreshold;
      
      print('🔧 임계값 검증 및 수정:');
      print('   - 원본 buyThreshold: $buyThreshold → 최종: $finalBuyThreshold');
      print('   - 원본 sellThreshold: $sellThreshold → 최종: $finalSellThreshold');
      
      // 임계값이 수정된 경우 DB에 저장
      if (finalBuyThreshold != buyThreshold || finalSellThreshold != sellThreshold) {
        print('💾 임계값 수정사항을 DB에 저장합니다.');
        await _repository.updateInvestmentStyle(
          styleName: styleName,
          partialProfit: partialProfit,
          fullProfit: fullProfit,
          stopLoss: stopLoss,
          positionSize: positionSize,
          maxStocks: maxStocks,
          dailyLossLimit: dailyLossLimit,
          buyThreshold: finalBuyThreshold,
          sellThreshold: finalSellThreshold,
        );
      }
      
      return {
        'partialProfit': partialProfit,
        'partialProfitRatio': 50.0, // 부분익절 비율 (50%)
        'fullProfit': fullProfit,
        'stopLoss': stopLoss,
        'positionSize': positionSize,
        'maxStocks': maxStocks,
        'dailyLossLimit': dailyLossLimit,
        'buyThreshold': finalBuyThreshold,
        'sellThreshold': finalSellThreshold,
      };
      
    } catch (e) {
      print('❌ 스타일 파라미터 로드 실패: $e');
      // 오류 발생 시 기본값 반환
      return _getDefaultStyleSettingsForStyle(style);
    }
  }
  
  // SharedPreferences에서 SQLite로 마이그레이션
  Future<void> _migrateSharedPrefsToSQLite(InvestmentStyle style, double? buyThreshold, double? sellThreshold) async {
    try {
      final styleName = _getStyleName(style);
      final currentSettings = await _repository.getInvestmentStyle(styleName);
      
      if (currentSettings != null) {
        // 기존 설정에 매수/매도 임계값만 업데이트
        await _repository.updateInvestmentStyle(
          styleName: styleName,
          partialProfit: currentSettings['partial_profit'] ?? 4.0,
          fullProfit: currentSettings['full_profit'] ?? 8.0,
          stopLoss: currentSettings['stop_loss'] ?? -2.5,
          positionSize: currentSettings['position_size'] ?? 0.05,
          maxStocks: currentSettings['max_stocks'] ?? 4,
          dailyLossLimit: currentSettings['daily_loss_limit'] ?? 3.0,
                buyThreshold: buyThreshold ?? currentSettings['buy_threshold'],
      sellThreshold: sellThreshold ?? currentSettings['sell_threshold'],
        );
      } else {
        // 새로운 스타일 설정 생성
        await _repository.saveInvestmentStyle(
          styleName: styleName,
          partialProfit: 4.0,
          fullProfit: 8.0,
          stopLoss: -2.5,
          positionSize: 0.05,
          maxStocks: 4,
          dailyLossLimit: 3.0,
                buyThreshold: buyThreshold ?? 0.0,
      sellThreshold: sellThreshold ?? 0.0,
        );
      }
      
      print('✅ SharedPreferences → SQLite 마이그레이션 완료: $styleName');
    } catch (e) {
      print('❌ SharedPreferences → SQLite 마이그레이션 실패: $e');
    }
  }

  // 특정 스타일의 기본 설정 반환 (슬라이더 범위에 맞춤)
  Map<String, dynamic> _getDefaultStyleSettingsForStyle(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return {
          'partialProfit': 3.0,  // 표 기준
          'partialProfitRatio': 50.0, // 부분익절 비율 (50%)
          'fullProfit': 7.0,    // 표 기준
          'stopLoss': -3.0,      // 표 기준
          'positionSize': 0.05,  // 5% 투자비율
          'maxStocks': 3,        // 표 기준
          'dailyLossLimit': -4.0, // 표 기준 (음수)
          'buyThreshold': 0.4,   // 표 기준
          'sellThreshold': -0.1, // 표 기준
        };
      case InvestmentStyle.moderate:
        return {
          'partialProfit': 5.0,  // 표 기준
          'partialProfitRatio': 50.0, // 부분익절 비율 (50%)
          'fullProfit': 10.0,    // 표 기준
          'stopLoss': -5.0,      // 표 기준
          'positionSize': 0.10,  // 10% 투자비율
          'maxStocks': 4,        // 표 기준
          'dailyLossLimit': -6.0, // 표 기준 (음수)
          'buyThreshold': 0.35,  // 표 기준
          'sellThreshold': -0.15, // 표 기준
        };
      case InvestmentStyle.aggressive:
        return {
          'partialProfit': 7.0,  // 표 기준
          'partialProfitRatio': 50.0, // 부분익절 비율 (50%)
          'fullProfit': 15.0,    // 표 기준
          'stopLoss': -7.0,     // 표 기준
          'positionSize': 0.20,  // 20% 투자비율
          'maxStocks': 5,       // 표 기준
          'dailyLossLimit': -7.0, // 표 기준 (음수)
          'buyThreshold': 0.3,   // 표 기준
          'sellThreshold': -0.2, // 표 기준
        };
    }
  }

  // 투자 스타일별 임계값 반환 (동적)
  Map<String, double> getStyleThresholds() {
    final defaults = _getDefaultThresholds();

    // 저장값이 없으면 스타일 기본 임계값 반환
    if (_currentStyleSettings == null) {
      return defaults;
    }

    // 저장된 값 기반으로 구성(단일 출처: DB 저장값 + 스타일 기본)
    final rsiOversold = (_currentStyleSettings!['rsi_condition'] ?? defaults['rsiOversold']!)
        .toDouble();
    final dynamic overboughtSetting = _currentStyleSettings!['rsi_overbought'];
    final double rsiOverbought = overboughtSetting is num
        ? overboughtSetting.toDouble()
        : defaults['rsiOverbought']!; // 대칭 금지, 스타일 기본값 사용

    final volumeThreshold = (_currentStyleSettings!['volume_condition'] ??
            defaults['volumeThreshold']!)
        .toDouble();

    return {
      'rsiOversold': rsiOversold,
      'rsiOverbought': rsiOverbought,
      'volumeThreshold': volumeThreshold,
      'momentumThreshold': _getMomentumThreshold(),
    };
  }

  // 기본 임계값 반환
  Map<String, double> _getDefaultThresholds() {
    switch (_currentStyle) {
      case InvestmentStyle.conservative:
        return {
          'rsiOversold': 35.0,
          'rsiOverbought': 65.0,
          'volumeThreshold': 1.2,  // 120% (기존 1.8에서 수정)
          'momentumThreshold': 0.7,
        };
      case InvestmentStyle.moderate:
        return {
          'rsiOversold': 30.0,
          'rsiOverbought': 70.0,
          'volumeThreshold': 1.0,  // 100% (기존 1.5에서 수정)
          'momentumThreshold': 0.6,
        };
      case InvestmentStyle.aggressive:
        return {
          'rsiOversold': 45.0,
          'rsiOverbought': 75.0,
          'volumeThreshold': 0.8,  // 80% (기존 1.2에서 수정)
          'momentumThreshold': 0.5,
        };
    }
  }

  // 모멘텀 임계값 계산
  double _getMomentumThreshold() {
    switch (_currentStyle) {
      case InvestmentStyle.conservative:
        return 0.7;
      case InvestmentStyle.moderate:
        return 0.6;
      case InvestmentStyle.aggressive:
        return 0.5;
    }
  }

  // 스타일에 따른 그라디언트 색상 반환
  List<Color> getGradientColors() {
    switch (_currentStyle) {
      case InvestmentStyle.conservative:
        return [
          const Color(0xFF4CAF50), // 밝은 초록색
          const Color(0xFF388E3C), // 중간 초록색
          const Color(0xFF2E7D32), // 진한 초록색
        ];
      case InvestmentStyle.moderate:
        return [
          const Color(0xFF4A90E2), // 밝은 파란색
          const Color(0xFF357ABD), // 중간 파란색
          const Color(0xFF2E5A8A), // 진한 파란색
        ];
      case InvestmentStyle.aggressive:
        return [
          const Color(0xFFE53935), // 밝은 빨간색
          const Color(0xFFD32F2F), // 중간 빨간색
          const Color(0xFFC62828), // 진한 빨간색
        ];
    }
  }

  // 스타일에 따른 앱바 색상 반환
  Color getAppBarColor() {
    switch (_currentStyle) {
      case InvestmentStyle.conservative:
        return const Color(0xFF4CAF50);
      case InvestmentStyle.moderate:
        return const Color(0xFF3B5BA9);
      case InvestmentStyle.aggressive:
        return const Color(0xFFE53935);
    }
  }

  // 스타일에 따른 테마 색상 반환
  Color getThemeColor() {
    switch (_currentStyle) {
      case InvestmentStyle.conservative:
        return const Color(0xFF4CAF50);
      case InvestmentStyle.moderate:
        return const Color(0xFF3B5BA9);
      case InvestmentStyle.aggressive:
        return const Color(0xFFE53935);
    }
  }

  // 현재 스타일 반환
  Future<InvestmentStyle> getCurrentStyle() async {
    return _currentStyle;
  }

  // 스타일 이름 반환
  String getStyleName() {
    switch (_currentStyle) {
      case InvestmentStyle.conservative:
        return '안정적 투자';
      case InvestmentStyle.moderate:
        return '일반적 투자';
      case InvestmentStyle.aggressive:
        return '공격적 투자';
    }
  }

  // 특정 스타일의 이름 반환 (백테스팅용)
  String _getStyleName(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return '안정적 투자';
      case InvestmentStyle.moderate:
        return '일반적 투자';
      case InvestmentStyle.aggressive:
        return '공격적 투자';
    }
  }

  // 커스터마이징 모드 상태 텍스트 반환
  String getCustomModeStatus() {
    return _isCustomMode ? '사용자 커스터마이징' : 'AI 최적화';
  }

  // 커스터마이징 모드 경고 메시지 반환
  String getCustomModeWarning() {
    if (_isCustomMode) {
      return '⚠️ AI 최적화된 설정을 변경합니다.\n책임은 사용자에게 있습니다.';
    }
    return '';
  }

  // 스타일 설정 업데이트 (현재 스타일)
  Future<void> updateStyleSettings(Map<String, dynamic> settings) async {
    await updateStyleSettingsFor(_currentStyle, settings);
  }

  // 스타일 설정 업데이트 (지정 스타일)
  Future<void> updateStyleSettingsFor(InvestmentStyle style, Map<String, dynamic> settings) async {
    try {
      final styleName = _getStyleName(style);
      
      print('🔄 스타일 설정 업데이트 시작: $styleName');
      print('   - 받은 settings: $settings');
      print('   - buy_threshold 값: ${settings['buy_threshold']}');
      print('   - sell_threshold 값: ${settings['sell_threshold']}');
      
      final buyThreshold = settings['buy_threshold'];
      final sellThreshold = settings['sell_threshold'];
      
      if (buyThreshold == null || sellThreshold == null) {
        print('⚠️ 매수/매도 임계값이 설정되지 않았습니다.');
        return;
      }
      
      print('   - 최종 buyThreshold: $buyThreshold');
      print('   - 최종 sellThreshold: $sellThreshold');
      
      await _repository.updateInvestmentStyle(
        styleName: styleName,
        partialProfit: settings['partial_profit'] ?? 4.0,
        fullProfit: settings['full_profit'] ?? 8.0,
        stopLoss: settings['stop_loss'] ?? -2.5,  // 음수로 수정
        positionSize: settings['position_size'] ?? 0.05,
        maxStocks: settings['max_stocks'] ?? 4,
        dailyLossLimit: settings['daily_loss_limit'] ?? -3.0,  // 음수로 수정
        buyThreshold: buyThreshold,
        sellThreshold: sellThreshold,
      );
      
      // 현재 스타일일 경우에만 현재 설정 갱신/브로드캐스트
      if (style == _currentStyle) {
        _currentStyleSettings = await _repository.getInvestmentStyle(styleName);
        _styleSettingsController.add(_currentStyleSettings!);
      }

      // 전역 동기화를 위해 모든 저장 가능한 파라미터를 SharedPreferences에도 동기 저장
      try {
        await _syncSettingsToPrefsFor(style, settings);
      } catch (_) {}
      
      print('✅ 스타일 설정 업데이트 완료: $styleName');
    } catch (e) {
      print('❌ 스타일 설정 업데이트 실패: $e');
    }
  }

  // 모든 파라미터를 SharedPreferences에 키(prefix+key)로 동기 저장 (현재 스타일)
  Future<void> _syncSettingsToPrefs(Map<String, dynamic> settings) async {
    await _syncSettingsToPrefsFor(_currentStyle, settings);
  }

  // 모든 파라미터를 SharedPreferences에 키(prefix+key)로 동기 저장 (지정 스타일)
  Future<void> _syncSettingsToPrefsFor(InvestmentStyle style, Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = '${style.name}_';
    for (final entry in settings.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is num) {
        // 정수는 double로도 저장되지만, 원형 값 보존을 위해 타입별 저장 시도
        if (value is int) {
          await prefs.setInt('$prefix$key', value);
        } else {
          await prefs.setDouble('$prefix$key', value.toDouble());
        }
      } else if (value is bool) {
        await prefs.setBool('$prefix$key', value);
      } else if (value is String) {
        await prefs.setString('$prefix$key', value);
      }
    }
  }

  // 리소스 정리
  void dispose() {
    _styleController.close();
    _customModeController.close();
    _styleSettingsController.close();
  }
}
