import 'package:flutter/material.dart';
import '../../core/trading/investment_style_manager.dart';
import '../../core/trading/investment_style.dart';

/// 투자스타일별 지표 설정 화면
class InvestmentStyleSettingsScreen extends StatefulWidget {
  const InvestmentStyleSettingsScreen({super.key});

  @override
  State<InvestmentStyleSettingsScreen> createState() => _InvestmentStyleSettingsScreenState();
}

class _InvestmentStyleSettingsScreenState extends State<InvestmentStyleSettingsScreen> {
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  
  // 현재 선택된 스타일
  InvestmentStyle _selectedStyle = InvestmentStyle.moderate; // 초기값, 로드 시 실제 값으로 변경됨
  
  // 사용자 커스터마이징 모드 (기본적으로 꺼진 상태)
  bool _isCustomMode = false;
  
  // 슬라이더 값들 (안전한 초기값 - 데이터 로드 전까지 사용)
  double _partialProfit = 5.0;
  double _fullProfit = 10.0;
  double _stopLoss = -5.0;        // 음수로 저장 (범위: -15.0 ~ -1.0)
  double _buyThreshold = 0.35;    // 양수로 저장
  double _sellThreshold = -0.15;  // 음수로 저장 (범위: -0.5 ~ 0.0)
  double _investmentRatio = 10.0; // 양수로 저장
  double _maxStocks = 4.0;        // 양수로 저장
  double _dailyLossLimit = -5.0;  // 음수로 저장 (범위: -15.0 ~ -1.0)
  
  @override
  void initState() {
    super.initState();
    _initializeAndLoadSettings();
  }

  /// 초기화 및 설정 로드
  void _initializeAndLoadSettings() async {
    try {
      // 데이터베이스 초기화
      await _styleManager.initialize();
      
      // 현재 설정 로드
      _loadCurrentSettings();
    } catch (e) {
      print('❌ 초기화 실패: $e');
      _loadDefaultSettings();
    }
  }

  /// 기존 데이터 정리 (양수로 저장된 음수 값들을 음수로 변환)
  Future<void> _fixExistingData() async {
    try {
      print('🔧 기존 데이터 정리 시작...');
      
      for (final style in InvestmentStyle.values) {
        final styleSettings = await _styleManager.getStyleParameters(style);
        if (styleSettings != null) {
          final fixedSettings = <String, dynamic>{};
          bool needsUpdate = false;
          
          // stopLoss 정리 (양수면 음수로 변환)
          final stopLoss = (styleSettings['stopLoss'] as num?)?.toDouble();
          if (stopLoss != null && stopLoss > 0) {
            fixedSettings['stop_loss'] = -stopLoss;
            needsUpdate = true;
            print('🔧 ${_getStyleName(style)} stopLoss 수정: $stopLoss -> ${-stopLoss}');
          }
          
          // dailyLossLimit 정리 (양수면 음수로 변환)
          final dailyLossLimit = (styleSettings['dailyLossLimit'] as num?)?.toDouble();
          if (dailyLossLimit != null && dailyLossLimit > 0) {
            fixedSettings['daily_loss_limit'] = -dailyLossLimit;
            needsUpdate = true;
            print('🔧 ${_getStyleName(style)} dailyLossLimit 수정: $dailyLossLimit -> ${-dailyLossLimit}');
          }
          
          // sellThreshold 정리 (양수면 음수로 변환)
          final sellThreshold = (styleSettings['sellThreshold'] as num?)?.toDouble();
          if (sellThreshold != null && sellThreshold > 0) {
            fixedSettings['sell_threshold'] = -sellThreshold;
            needsUpdate = true;
            print('🔧 ${_getStyleName(style)} sellThreshold 수정: $sellThreshold -> ${-sellThreshold}');
          }
          
          if (needsUpdate) {
            await _styleManager.updateStyleSettingsFor(style, fixedSettings);
            print('✅ ${_getStyleName(style)} 데이터 정리 완료');
          } else {
            print('✅ ${_getStyleName(style)} 데이터 정리 불필요 (이미 올바른 형식)');
          }
        }
      }
      
      print('🎉 모든 데이터 정리 완료!');
    } catch (e) {
      print('❌ 기존 데이터 정리 실패: $e');
    }
  }

  void _loadCurrentSettings() async {
    try {
      // 현재 스타일 로드
      final currentStyle = await _styleManager.getCurrentStyle();
      setState(() {
        _selectedStyle = currentStyle;
      });
      
      // 커스터마이징 모드 로드
      final isCustomMode = await _styleManager.getCustomMode();
      setState(() {
        _isCustomMode = isCustomMode;
      });
      
      // 데이터베이스에서 현재 스타일의 설정값 로드
      final styleName = _getStyleName(_selectedStyle);
      final styleSettings = await _styleManager.getStyleParameters(_selectedStyle);
      
       if (styleSettings != null) {
         setState(() {
           _partialProfit = (styleSettings['partialProfit'] as num?)?.toDouble() ?? 8.0;
           _fullProfit = (styleSettings['fullProfit'] as num?)?.toDouble() ?? 15.0;
           
           // stopLoss: 음수로 저장되므로 그대로 사용
           _stopLoss = (styleSettings['stopLoss'] as num?)?.toDouble() ?? -3.0;
           
           _buyThreshold = (styleSettings['buyThreshold'] as num?)?.toDouble() ?? 0.2;
           
           // sellThreshold: 음수로 저장되므로 그대로 사용
           _sellThreshold = (styleSettings['sellThreshold'] as num?)?.toDouble() ?? -0.1;
           
           // positionSize는 소수(0.05)로 저장되므로 백분율로 변환 (0.05 -> 5.0)
           _investmentRatio = ((styleSettings['positionSize'] as num?)?.toDouble() ?? 0.05) * 100;
           _maxStocks = (styleSettings['maxStocks'] as num?)?.toDouble() ?? 2.0;
           
           // dailyLossLimit: 음수로 저장되므로 그대로 사용
           _dailyLossLimit = (styleSettings['dailyLossLimit'] as num?)?.toDouble() ?? -4.0;
         });
        
        print('📊 스타일 설정 로드 완료: $styleName');
        print('   - 부분익절: $_partialProfit%');
        print('   - 전체익절: $_fullProfit%');
        print('   - 손절: $_stopLoss%');
        print('   - 매수임계값: $_buyThreshold');
        print('   - 매도임계값: $_sellThreshold');
        print('   - 투자비율: $_investmentRatio%');
        print('   - 최대종목: $_maxStocks개');
        print('   - 일일손실한도: $_dailyLossLimit%');
      } else {
        // 데이터베이스에 설정이 없으면 기본값 사용
        _loadDefaultSettings();
      }
    } catch (e) {
      print('❌ 스타일 설정 로드 실패: $e');
      _loadDefaultSettings();
    }
  }

  void _loadDefaultSettings() {
    // 표에 명시된 기본값 사용 (음수는 음수로, 양수는 양수로 통일)
    switch (_selectedStyle) {
      case InvestmentStyle.conservative:
        _partialProfit = 3.0;
        _fullProfit = 7.0;
        _stopLoss = -3.0;        // 음수로 통일
        _buyThreshold = 0.4;
        _sellThreshold = -0.1;   // 음수로 통일
        _investmentRatio = 5.0;
        _maxStocks = 3.0;
        _dailyLossLimit = -4.0;  // 음수로 통일
        break;
      case InvestmentStyle.moderate:
        _partialProfit = 5.0;
        _fullProfit = 10.0;
        _stopLoss = -5.0;        // 음수로 통일
        _buyThreshold = 0.35;
        _sellThreshold = -0.15;  // 음수로 통일
        _investmentRatio = 10.0;
        _maxStocks = 4.0;
        _dailyLossLimit = -6.0;  // 음수로 통일
        break;
      case InvestmentStyle.aggressive:
        _partialProfit = 7.0;
        _fullProfit = 15.0;
        _stopLoss = -7.0;        // 음수로 통일
        _buyThreshold = 0.3;
        _sellThreshold = -0.2;   // 음수로 통일
        _investmentRatio = 20.0;
        _maxStocks = 5.0;
        _dailyLossLimit = -7.0;  // 음수로 통일
        break;
    }
  }

  /// 특정 스타일의 설정 로드
  void _loadSettingsForStyle(InvestmentStyle style) async {
    try {
      // 데이터베이스에서 해당 스타일의 설정값 로드
      final styleSettings = await _styleManager.getStyleParameters(style);
      
      if (styleSettings != null) {
        setState(() {
          _partialProfit = (styleSettings['partialProfit'] as num?)?.toDouble() ?? 8.0;
          _fullProfit = (styleSettings['fullProfit'] as num?)?.toDouble() ?? 15.0;
          
          // stopLoss: 음수로 저장되므로 그대로 사용
          _stopLoss = (styleSettings['stopLoss'] as num?)?.toDouble() ?? -3.0;
          
          _buyThreshold = (styleSettings['buyThreshold'] as num?)?.toDouble() ?? 0.2;
          
          // sellThreshold: 음수로 저장되므로 그대로 사용
          _sellThreshold = (styleSettings['sellThreshold'] as num?)?.toDouble() ?? -0.1;
          
          // positionSize는 소수(0.05)로 저장되므로 백분율로 변환 (0.05 -> 5.0)
          _investmentRatio = ((styleSettings['positionSize'] as num?)?.toDouble() ?? 0.05) * 100;
          _maxStocks = (styleSettings['maxStocks'] as num?)?.toDouble() ?? 2.0;
          
          // dailyLossLimit: 음수로 저장되므로 그대로 사용
          _dailyLossLimit = (styleSettings['dailyLossLimit'] as num?)?.toDouble() ?? -4.0;
        });
        
        print('📊 ${_getStyleName(style)} 스타일 설정 로드 완료');
        print('🎨 현재 선택된 스타일: ${_getStyleName(_selectedStyle)}');
        print('🎨 스타일 색상: ${_getStyleColor(_selectedStyle)}');
      } else {
        // 데이터베이스에 설정이 없으면 기본값 사용
        _loadDefaultSettings();
      }
    } catch (e) {
      print('❌ ${_getStyleName(style)} 스타일 설정 로드 실패: $e');
      _loadDefaultSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          // 헤더와 스타일 선택 영역을 하나의 그라디언트로 연결
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _getStyleGradientColors(_selectedStyle),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: Column(
              children: [
                // 헤더 영역
                Container(
                  height: kToolbarHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Expanded(
                        child: Text(
                          '투자 스타일별 지표 설정',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 48), // 뒤로가기 버튼과 균형 맞추기
                    ],
                  ),
                ),
                // 투자 스타일 선택 탭
                _buildStyleSelectionTabs(),
              ],
            ),
          ),
          // 메인 콘텐츠
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              
              // 사용자 커스터마이징 토글
              _buildCustomizationToggle(),
              
              // 사용자 조정 영역
              _isCustomMode ? _buildUserAdjustmentArea() : _buildUserAdjustmentPreview(),
              
              const SizedBox(height: 24),
              
                ],
              ),
            ),
          ),
          // 하단 고정 버튼들
          Container(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: _buildBottomButtons(),
          ),
        ],
      ),
    );
  }

  /// 투자 스타일 선택 탭
  Widget _buildStyleSelectionTabs() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              _buildStyleTab(InvestmentStyle.conservative, '안정적 투자', _getStyleIcon(InvestmentStyle.conservative)),
              _buildStyleTab(InvestmentStyle.moderate, '일반적 투자', _getStyleIcon(InvestmentStyle.moderate)),
              _buildStyleTab(InvestmentStyle.aggressive, '공격적 투자', _getStyleIcon(InvestmentStyle.aggressive)),
            ],
          ),
        ),
        // 선택된 스타일에 따라 밑줄 위치 변경
        Row(
          children: [
            // 안정적 투자 탭 아래
            Expanded(
              child: Container(
                height: 3.0,
                padding: const EdgeInsets.symmetric(horizontal: 20), // 양쪽 패딩
                child: _selectedStyle == InvestmentStyle.conservative
                    ? Container(
                        width: 60,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2.0),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            // 일반적 투자 탭 아래
            Expanded(
              child: Container(
                height: 3.0,
                padding: const EdgeInsets.symmetric(horizontal: 20), // 양쪽 패딩
                child: _selectedStyle == InvestmentStyle.moderate
                    ? Container(
                        width: 60,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2.0),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            // 공격적 투자 탭 아래
            Expanded(
              child: Container(
                height: 3.0,
                padding: const EdgeInsets.symmetric(horizontal: 20), // 양쪽 패딩
                child: _selectedStyle == InvestmentStyle.aggressive
                    ? Container(
                        width: 60,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2.0),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ],
    );
  }


  /// 스타일 탭
  Widget _buildStyleTab(InvestmentStyle style, String title, IconData icon) {
    final isSelected = _selectedStyle == style;
    
    return Expanded(
      child: GestureDetector(
        onTap: () {
          print('🔄 스타일 변경: ${_getStyleName(style)}');
          setState(() {
            _selectedStyle = style;
          });
          _loadSettingsForStyle(style);
          print('🎨 변경된 스타일 색상: ${_getStyleColor(_selectedStyle)}');
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent, // 모든 스타일 탭을 투명하게
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.5), // 선택되지 않은 스타일은 더 투명하게
                size: 28, // 아이콘 크기 증가
              ),
              const SizedBox(height: 8), // 텍스트와 밑줄 사이 마진 8dp
              Text(
                title,
                style: TextStyle(
                  fontSize: 14, // 글자 크기 증가
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, // 선택된 스타일은 더 굵게
                  color: isSelected ? Colors.white : Colors.white.withOpacity(0.5), // 선택되지 않은 스타일은 더 투명하게
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 사용자 커스터마이징 토글
  Widget _buildCustomizationToggle() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit, color: _getStyleColor(_selectedStyle), size: 20),
                const SizedBox(width: 8),
                const Text(
                  '사용자 커스터마이징',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _isCustomMode,
                  onChanged: (value) {
                    setState(() {
                      _isCustomMode = value;
                    });
                  },
                  activeColor: _getStyleColor(_selectedStyle),
                ),
              ],
            ),
            if (_isCustomMode) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.warning, color: _getStyleColor(_selectedStyle), size: 16),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'AI 최적화된 설정을 변경합니다. 책임은 사용자에게 있습니다.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }




  /// 사용자 조정 영역
  Widget _buildUserAdjustmentArea() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             // 사용자 조정 영역 제목 제거
            const SizedBox(height: 16),
            
            // 매도 조건 설정
            _buildSellConditionSettings(),
            const SizedBox(height: 16),
            
            // 투자 관리 설정
            _buildInvestmentManagementSettings(),
          ],
        ),
      ),
    );
  }

  /// 사용자 조정 영역 미리보기 (토글이 꺼진 상태)
  Widget _buildUserAdjustmentPreview() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 매도 조건 설정 (비활성화 상태)
            _buildSellConditionSettings(),
            const SizedBox(height: 16),
            
            // 투자 관리 설정 (비활성화 상태)
            _buildInvestmentManagementSettings(),
          ],
        ),
      ),
    );
  }

  /// 매도 조건 설정
  Widget _buildSellConditionSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              color: _getStyleColor(_selectedStyle),
            ),
            const SizedBox(width: 8),
            const Text(
              '매도 조건 설정',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        _buildSlider('부분 익절', _partialProfit, (value) => setState(() => _partialProfit = value), '${_partialProfit.toStringAsFixed(1)}%', '일부 보유주식 익절 기준'),
        
        _buildSlider('전체 익절', _fullProfit, (value) => setState(() => _fullProfit = value), '${_fullProfit.toStringAsFixed(1)}%', '전체 보유주식 익절 기준'),
        
        _buildSlider('손절 기준', _stopLoss, (value) => setState(() => _stopLoss = value), '${_stopLoss.toStringAsFixed(1)}%', '손절매 기준 (음수값)'),
        
        _buildSlider('매수 임계값', _buyThreshold, (value) => setState(() => _buyThreshold = value), '${_buyThreshold.toStringAsFixed(2)}점', '7가지 동적 지표 종합 점수 기준 (높을수록 엄격)'),
        
        _buildSlider('매도 임계값', _sellThreshold, (value) => setState(() => _sellThreshold = value), '${_sellThreshold.toStringAsFixed(2)}점', '7가지 동적 지표 종합 점수 기준 (낮을수록 빠른 매도)'),
      ],
    );
  }

  /// 투자 관리 설정
  Widget _buildInvestmentManagementSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              color: _getStyleColor(_selectedStyle),
            ),
            const SizedBox(width: 8),
            const Text(
              '투자 관리 설정',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        _buildSlider('투자 비율', _investmentRatio, (value) => setState(() => _investmentRatio = value), '${_investmentRatio.toStringAsFixed(1)}%', '자본금 대비 투자 비율'),
        
        _buildSlider('최대 종목 수', _maxStocks, (value) => setState(() => _maxStocks = value), '${_maxStocks.toInt()}개', '동시 보유 가능한 최대 종목 수'),
        
        _buildSlider('일일 손실 한도', _dailyLossLimit, (value) => setState(() => _dailyLossLimit = value), '${_dailyLossLimit.toStringAsFixed(1)}%', '일일 최대 손실 한도'),
      ],
    );
  }

  /// 슬라이더 위젯
  Widget _buildSlider(String label, double value, Function(double) onChanged, String displayValue, String description) {
    final bool isEnabled = _isCustomMode;
    
    return Card(
      elevation: 1,
      color: Colors.grey[200],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 라벨과 값
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isEnabled ? Colors.black87 : Colors.grey[600],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isEnabled ? _getStyleColor(_selectedStyle).withOpacity(0.1) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isEnabled ? _getStyleColor(_selectedStyle).withOpacity(0.3) : Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    displayValue,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isEnabled ? _getStyleColor(_selectedStyle) : Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 슬라이더
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: isEnabled ? _getStyleColor(_selectedStyle) : Colors.grey[500],
                inactiveTrackColor: Colors.grey[400],
                thumbColor: isEnabled ? _getStyleColor(_selectedStyle) : Colors.grey[500],
                overlayColor: isEnabled ? _getStyleColor(_selectedStyle).withOpacity(0.2) : Colors.grey.withOpacity(0.1),
                trackHeight: 6,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
                disabledActiveTrackColor: Colors.grey[500],
                disabledInactiveTrackColor: Colors.grey[400],
                disabledThumbColor: Colors.grey[500],
              ),
              child: Slider(
                value: value,
                onChanged: isEnabled ? onChanged : null,
                min: _getSliderMin(label),
                max: _getSliderMax(label),
                divisions: 100,
              ),
            ),
            const SizedBox(height: 4),
            // 슬라이더 범위 표시
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_getSliderMin(label).toStringAsFixed(1)}${_getSliderUnit(label)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${_getSliderMax(label).toStringAsFixed(1)}${_getSliderUnit(label)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 설명
            Text(
              description,
              style: TextStyle(
                fontSize: 13,
                color: isEnabled ? Colors.black87 : Colors.grey[500],
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 슬라이더 최소값
  double _getSliderMin(String label) {
    switch (label) {
      case '부분 익절': return 1.0;
      case '전체 익절': return 5.0;
      case '손절 기준': return -15.0; // 범위 확장
      case '매수 임계값': return 0.1;
      case '매도 임계값': return -0.5;
      case '투자 비율': return 1.0;
      case '최대 종목 수': return 1.0;
      case '일일 손실 한도': return -15.0; // 범위 확장
      default: return 0.0;
    }
  }

  /// 슬라이더 최대값
  double _getSliderMax(String label) {
    switch (label) {
      case '부분 익절': return 15.0;
      case '전체 익절': return 25.0;
      case '손절 기준': return -1.0;
      case '매수 임계값': return 0.8;
      case '매도 임계값': return 0.0;
      case '투자 비율': return 30.0;
      case '최대 종목 수': return 10.0;
      case '일일 손실 한도': return -1.0;
      default: return 100.0;
    }
  }

  /// 슬라이더 단위
  String _getSliderUnit(String label) {
    switch (label) {
      case '부분 익절': return '%';
      case '전체 익절': return '%';
      case '손절 기준': return '%';
      case '매수 임계값': return '점';
      case '매도 임계값': return '점';
      case '투자 비율': return '%';
      case '최대 종목 수': return '개';
      case '일일 손실 한도': return '%';
      default: return '';
    }
  }

  /// 하단 버튼들
  Widget _buildBottomButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _resetToDefaults,
            icon: const Icon(Icons.refresh),
            label: const Text('초기화'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[300],
              foregroundColor: Colors.grey[700],
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save),
            label: const Text('저장'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _getStyleColor(_selectedStyle),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 초기화
  void _resetToDefaults() async {
    setState(() {
      _loadDefaultSettings();
    });
    
    // 데이터베이스에도 기본값으로 저장
    try {
      final settings = {
         'partial_profit': _partialProfit,
         'full_profit': _fullProfit,
         'stop_loss': _stopLoss, // 음수 그대로 저장
         'buy_threshold': _buyThreshold,
         'sell_threshold': _sellThreshold, // 음수 그대로 저장
         'position_size': _investmentRatio / 100.0, // 백분율을 소수로 변환 (5.0 -> 0.05)
         'max_stocks': _maxStocks.toInt(),
         'daily_loss_limit': _dailyLossLimit, // 음수 그대로 저장
      };
      
      await _styleManager.updateStyleSettingsFor(_selectedStyle, settings);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('기본값으로 초기화되었습니다.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('초기화 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 설정 저장
  void _saveSettings() async {
    try {
      final settings = {
         'partial_profit': _partialProfit,
         'full_profit': _fullProfit,
         'stop_loss': _stopLoss, // 음수 그대로 저장
         'buy_threshold': _buyThreshold,
         'sell_threshold': _sellThreshold, // 음수 그대로 저장
         'position_size': _investmentRatio / 100.0, // 백분율을 소수로 변환 (5.0 -> 0.05)
         'max_stocks': _maxStocks.toInt(),
         'daily_loss_limit': _dailyLossLimit, // 음수 그대로 저장
      };
      
      await _styleManager.updateStyleSettingsFor(_selectedStyle, settings);
      await _styleManager.setStyle(_selectedStyle);
      await _styleManager.setCustomMode(_isCustomMode);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('설정이 저장되었습니다.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  /// 스타일 아이콘 반환
  IconData _getStyleIcon(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return Icons.security; // 방패 모양 아이콘으로 변경
      case InvestmentStyle.moderate:
        return Icons.balance;
      case InvestmentStyle.aggressive:
        return Icons.trending_up;
    }
  }

  /// 스타일 색상 반환
  Color _getStyleColor(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return Colors.green[600]!;
      case InvestmentStyle.moderate:
        return const Color(0xFF3B5BA9);
      case InvestmentStyle.aggressive:
        return Colors.red[600]!;
    }
  }

  /// 스타일별 그라디언트 색상 반환 (다른 곳과 동일)
  List<Color> _getStyleGradientColors(InvestmentStyle style) {
    switch (style) {
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

  /// 스타일별 그라디언트 반환
  LinearGradient _getStyleGradient(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return LinearGradient(
          colors: [Colors.green[600]!, Colors.green[800]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case InvestmentStyle.moderate:
        return LinearGradient(
          colors: [const Color(0xFF3B5BA9), const Color(0xFF2A4A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case InvestmentStyle.aggressive:
        return LinearGradient(
          colors: [Colors.red[600]!, Colors.red[800]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  /// 스타일 이름 반환
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

  /// 투자 스타일 설명
  String _getStyleDescription(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return '안전한 투자로 리스크를 최소화하는 전략. RSI 30 이하에서 매수, 70 이상에서 매도.';
      case InvestmentStyle.moderate:
        return '균형잡힌 투자로 안정성과 수익성을 모두 고려하는 전략. RSI 35 이하에서 매수, 65 이상에서 매도.';
      case InvestmentStyle.aggressive:
        return '적극적인 투자로 높은 수익을 추구하는 전략. RSI 40 이하에서 매수, 60 이상에서 매도.';
    }
  }
}
