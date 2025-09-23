import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:charset_converter/charset_converter.dart';

/// 종목 마스터 정보 파서
/// KIS에서 제공하는 마스터 파일을 파싱하여 종목 정보를 제공
class StockMasterParser {
  static final StockMasterParser _instance = StockMasterParser._internal();
  factory StockMasterParser() => _instance;
  StockMasterParser._internal();

  // 종목 데이터 저장소
  Map<String, Map<String, dynamic>> _kospiStocks = {};
  Map<String, Map<String, dynamic>> _kosdaqStocks = {};
  Map<String, Map<String, dynamic>> _nasdaqStocks = {};
  Map<String, Map<String, dynamic>> _nyseStocks = {};
  bool _isInitialized = false;
  bool _loggedNasdaqSample = false;
  bool _loggedNyseSample = false;

  /// 초기화 - 스플래시 화면에서 호출 (최적화된 버전)
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    print('📈 종목 마스터 데이터 로드 시작...');
    
    // 병렬로 실행하여 속도 향상
    try {
      await Future.wait([
        _loadKospiMasterData(),
        _loadKosdaqMasterData(),
        _loadNasdaqMasterData(),
        _loadNysemasterData(),
      ]);
      
      _isInitialized = true;
      print('✅ 종목 마스터 데이터 로드 완료');
    } catch (e) {
      print('❌ 종목 마스터 데이터 로드 실패: $e');
      // 일부 실패해도 계속 진행
      _isInitialized = true;
    }
  }

  /// KOSPI 마스터 데이터 로드
  Future<void> _loadKospiMasterData() async {
    try {
      final kospiData = await _parseMasterFile('assets/stock_info/kospi_code.mst.zip');
      if (kospiData.isNotEmpty) {
        _kospiStocks = kospiData;
        print('✅ KOSPI 마스터 파일 파싱 완료: ${_kospiStocks.length}개');
      } else {
        print('⚠️ KOSPI 마스터 파일 파싱 실패 - 빈 데이터');
      }
    } catch (e) {
      print('❌ KOSPI 마스터 파일 파싱 실패: $e');
    }
  }

  /// KOSDAQ 마스터 데이터 로드
  Future<void> _loadKosdaqMasterData() async {
    try {
      final kosdaqData = await _parseMasterFile('assets/stock_info/kosdaq_code.mst.zip');
      if (kosdaqData.isNotEmpty) {
        _kosdaqStocks = kosdaqData;
        print('✅ KOSDAQ 마스터 파일 파싱 완료: ${_kosdaqStocks.length}개');
      } else {
        print('⚠️ KOSDAQ 마스터 파일 파싱 실패 - 빈 데이터');
      }
    } catch (e) {
      print('❌ KOSDAQ 마스터 파일 파싱 실패: $e');
    }
  }

  /// NASDAQ 마스터 데이터 로드
  Future<void> _loadNasdaqMasterData() async {
    try {
      print('🇺🇸 나스닥 종목 데이터 로드 시작...');
      
      // COD 파일 전용 파싱 함수 사용
      print('🔍 NASDAQ COD 파일 파싱 시작...');
      final stocks = await _parseCodFile('assets/stock_info/nasmst.cod.zip');
      print('🔍 NASDAQ COD 파일 파싱 완료: ${stocks.length}개 종목');
      
      if (stocks.isNotEmpty) {
        _nasdaqStocks = stocks;
        print('✅ 나스닥 종목 데이터 로드 완료: ${_nasdaqStocks.length}개');
        
        // 처음 10개 종목 출력
        print('📈 나스닥 종목 샘플 (처음 10개):');
        int count = 0;
        for (final entry in _nasdaqStocks.entries) {
          if (count >= 10) break;
          print('  ${entry.key}: ${entry.value['name']} (${entry.value['englishName']})');
          count++;
        }
      } else {
        print('⚠️ 나스닥 종목 데이터가 없습니다.');
        _nasdaqStocks = {};
      }
    } catch (e) {
      print('❌ 나스닥 종목 로드 실패: $e');
      print('❌ 오류 상세: ${e.toString()}');
      _nasdaqStocks = {};
    }
  }

  /// NYSE 마스터 데이터 로드
  Future<void> _loadNysemasterData() async {
    try {
      print('🏛️ 뉴욕증권거래소 종목 데이터 로드 시작...');
      
      // COD 파일 전용 파싱 함수 사용
      print('🔍 NYSE COD 파일 파싱 시작...');
      final stocks = await _parseCodFile('assets/stock_info/nysmst.cod.zip');
      print('🔍 NYSE COD 파일 파싱 완료: ${stocks.length}개 종목');
      
      if (stocks.isNotEmpty) {
        _nyseStocks = stocks;
        print('✅ 뉴욕증권거래소 종목 데이터 로드 완료: ${_nyseStocks.length}개');
      } else {
        print('⚠️ 뉴욕증권거래소 종목 데이터가 없습니다.');
        _nyseStocks = {};
      }
    } catch (e) {
      print('❌ 뉴욕증권거래소 종목 로드 실패: $e');
      print('❌ 오류 상세: ${e.toString()}');
      _nyseStocks = {};
    }
  }



  /// COD 파일 파싱 (NASDAQ/NYSE 전용)
  Future<Map<String, Map<String, dynamic>>> _parseCodFile(String filePath) async {
    try {
      // 파일 경로에서 시장 구분
      String market = 'NASDAQ';
      if (filePath.contains('nysmst.cod.zip')) {
        market = 'NYSE';
        print('🏛️ NYSE COD 파일 파싱 시작: $filePath');
      } else {
        print('🔍 NASDAQ COD 파일 파싱 시작: $filePath');
      }
      print('🔍 파일 경로 확인: $filePath');
      
      // 파일 존재 여부 확인
      ByteData data;
      try {
        data = await rootBundle.load(filePath);
        print('✅ COD 파일 로드 성공: ${data.lengthInBytes} bytes');
      } catch (e) {
        print('❌ COD 파일 로드 실패: $e');
        return {};
      }
      
      // ZIP 파일 읽기
      final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      print('📦 COD ZIP 파일 크기: ${bytes.length} bytes');
      
      // ZIP 압축 해제
      Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes);
        print('📁 COD ZIP 파일 내 파일 목록:');
        for (final file in archive) {
          print('  - ${file.name} (${file.size} bytes)');
        }
      } catch (e) {
        print('❌ COD ZIP 파일 압축 해제 실패: $e');
        return {};
      }
      
      // COD 파일 찾기 (더 유연하게)
      ArchiveFile? codFile;
      for (final file in archive) {
        print('🔍 파일 확인: ${file.name} (${file.size} bytes)');
        if (file.name.endsWith('.cod') || file.name.endsWith('.COD') || file.name.toLowerCase().contains('nasmst')) {
          codFile = file;
          print('✅ COD 파일 발견: ${file.name}');
          break;
        }
      }
      
      if (codFile == null) {
        print('❌ COD 파일을 찾을 수 없습니다: $filePath');
        print('🔍 사용 가능한 파일들:');
        for (final file in archive) {
          print('  - ${file.name} (${file.size} bytes)');
        }
        return {};
      }
      
      print('✅ COD 파일 발견: ${codFile.name} (${codFile.size} bytes)');
      
      // COD 파일 내용을 cp949로 디코딩 (파이썬 코드 참고)
      final List<int> codBytes = codFile.content as List<int>;
      final Uint8List codBytesUint8 = Uint8List.fromList(codBytes);
      
      String codContent;
      try {
        // cp949로 먼저 시도 (파이썬 코드와 동일)
        codContent = await CharsetConverter.decode('cp949', codBytesUint8);
        print('✅ COD 파일 cp949 디코딩 성공');
      } catch (e) {
        try {
          // cp949 실패 시 UTF-8로 시도
          codContent = await CharsetConverter.decode('utf-8', codBytesUint8);
          print('✅ COD 파일 UTF-8 디코딩 성공');
        } catch (e) {
          // UTF-8도 실패 시 ASCII로 시도
          codContent = await CharsetConverter.decode('ascii', codBytesUint8);
          print('✅ COD 파일 ASCII 디코딩 성공');
        }
      }
      
      print('📄 COD 파일 내용 샘플 (처음 1000자):');
      print(codContent.substring(0, codContent.length > 1000 ? 1000 : codContent.length));
      
      // 파일 내용에서 실제 종목 데이터 확인
      final allLines = codContent.split('\n');
      print('📋 COD 파일 총 라인 수: ${allLines.length}');
      
      // 처음 10개 라인 출력
      print('📋 COD 파일 처음 10개 라인:');
      for (int i = 0; i < allLines.length && i < 10; i++) {
        print('  라인 ${i + 1}: "${allLines[i]}"');
      }
      
      // COD 파일 파싱 (NASDAQ 형식)
      final Map<String, Map<String, dynamic>> stocks = {};
      final List<String> lines = allLines;
      print('📋 COD 총 라인 수: ${lines.length}');
      
      int validLines = 0;
      int invalidLines = 0;
      
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim().isEmpty) continue;
        
        try {
          // COD 파일 형식 분석 (탭 구분자 사용)
          List<String> parts = line.split('\t');
          
          // 빈 문자열 제거
          parts = parts.where((part) => part.trim().isNotEmpty).toList();
          
          if (parts.length >= 8) { // 최소 8개 컬럼 필요 (Symbol, Korea name 등)
            final symbol = parts[4].trim(); // Symbol 컬럼
            final koreaName = parts[6].trim(); // Korea name 컬럼
            final englishName = parts[7].trim(); // English name 컬럼
            
            // 유효한 종목코드인지 확인 (Symbol이 비어있지 않고 알파벳으로 구성)
            if (symbol.isNotEmpty && 
                RegExp(r'^[A-Z]{1,6}$').hasMatch(symbol) &&
                koreaName.isNotEmpty) {
              stocks[symbol] = {
                'code': symbol,
                'name': koreaName,
                'englishName': englishName,
                'market': market,
              };
              validLines++;
              
              // 처음 몇 개 종목 출력
              if (validLines <= 5) {
                print('  ✅ $symbol: $koreaName ($englishName)');
              }
            } else {
              invalidLines++;
              if (invalidLines <= 5) {
                print('  ❌ 무효한 종목코드: $symbol, 종목명: $koreaName');
              }
            }
          } else {
            invalidLines++;
            if (invalidLines <= 5) {
              print('  ❌ 라인 형식 오류: $line (parts: $parts)');
            }
          }
        } catch (e) {
          invalidLines++;
          if (invalidLines <= 5) {
            print('  ❌ COD 파싱 오류: $line - $e');
          }
        }
      }
      
      print('📊 COD 파일 파싱 완료: ${stocks.length}개 종목 (유효: $validLines, 무효: $invalidLines)');
      
      // 파싱된 종목이 없으면 빈 맵 반환
      if (stocks.isEmpty) {
        print('⚠️ NASDAQ 종목이 파싱되지 않았습니다.');
        return {};
      }
      
      return stocks;
      
    } catch (e) {
      print('❌ NASDAQ COD 파일 파싱 실패: $e');
      
      // 오류 발생 시에도 기본 NASDAQ 종목들 추가
      print('⚠️ 오류로 인해 기본 NASDAQ 종목들을 추가합니다.');
      return {};
    }
  }

  /// 마스터 파일 파싱 (실제 구현)
  Future<Map<String, Map<String, dynamic>>> _parseMasterFile(String filePath) async {
    try {
      print('🔍 마스터 파일 파싱 시작: $filePath');
      
      // ZIP 파일 읽기
      final ByteData data = await rootBundle.load(filePath);
      final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      print('📦 ZIP 파일 크기: ${bytes.length} bytes');
      
      // ZIP 압축 해제
      final Archive archive = ZipDecoder().decodeBytes(bytes);
      print('📁 ZIP 파일 내 파일 목록:');
      for (final file in archive) {
        print('  - ${file.name} (${file.size} bytes)');
      }
      
      // MST 파일 찾기
      ArchiveFile? mstFile;
      for (final file in archive) {
        if (file.name.endsWith('.mst')) {
          mstFile = file;
          break;
        }
      }
      
      if (mstFile == null) {
        print('❌ MST 파일을 찾을 수 없습니다: $filePath');
        return {};
      }
      
      print('✅ MST 파일 발견: ${mstFile.name} (${mstFile.size} bytes)');
      
      // MST 파일 내용을 CP949로 디코딩
      final List<int> mstBytes = mstFile.content as List<int>;
      final Uint8List mstBytesUint8 = Uint8List.fromList(mstBytes);
      final String mstContent = await CharsetConverter.decode('cp949', mstBytesUint8);
      
      print('📄 MST 파일 내용 샘플 (처음 500자):');
      print(mstContent.substring(0, mstContent.length > 500 ? 500 : mstContent.length));
      
      // MST 파일 파싱 (고정 길이 형식)
      final Map<String, Map<String, dynamic>> stocks = {};
      final List<String> lines = mstContent.split('\n');
      print('📋 총 라인 수: ${lines.length}');
      
      int validLines = 0;
      int invalidLines = 0;
      
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim().isEmpty) continue;
        
        try {
          // MST 파일은 고정 길이 형식
          // KOSPI: 단축코드(9자리) + 표준코드(12자리) + 한글명(나머지)
          // KOSDAQ: 단축코드(9자리) + 표준코드(12자리) + 한글종목명(나머지)
          
          if (line.length >= 21) {
            final shortCode = line.substring(0, 9).trim(); // 단축코드
            final standardCode = line.substring(9, 21).trim(); // 표준코드
            final fullName = line.substring(21).trim(); // 전체 종목명 (추가 데이터 포함)
            
            // 종목명에서 첫 번째 공백이나 특수문자 이전까지만 추출
            final name = fullName.split(RegExp(r'[^\w가-힣]')).first.trim();
            
            // 유효한 종목코드인지 확인 (6자리 숫자)
            if (shortCode.length == 6 && RegExp(r'^\d{6}$').hasMatch(shortCode) && name.isNotEmpty) {
              stocks[shortCode] = {
                'code': shortCode,
                'name': name,
                'market': filePath.contains('kospi') ? 'KOSPI' : 'KOSDAQ',
              };
              validLines++;
              
              // 처음 몇 개 종목 출력
              if (validLines <= 5) {
                print('  ✅ $shortCode: $name (${filePath.contains('kospi') ? 'KOSPI' : 'KOSDAQ'})');
              }
            } else {
              invalidLines++;
              if (invalidLines <= 5) {
                print('  ❌ 무효한 종목코드: $shortCode, 종목명: $name');
              }
            }
          } else {
            invalidLines++;
            if (invalidLines <= 5) {
              print('  ❌ 라인 길이 부족: ${line.length}자 (최소 21자 필요)');
            }
          }
        } catch (e) {
          invalidLines++;
          if (invalidLines <= 5) {
            print('  ❌ 파싱 오류: $line - $e');
          }
        }
      }
      
      print('📊 MST 파일 파싱 완료: ${stocks.length}개 종목 (유효: $validLines, 무효: $invalidLines)');
      return stocks;
      
    } catch (e) {
      print('❌ 마스터 파일 파싱 실패: $e');
      return {};
    }
  }

  /// 종목 검색
  List<Map<String, dynamic>> searchStocks(String query, {int offset = 0, int limit = 10}) {
    if (!_isInitialized) {
      print('⚠️ 종목 마스터 데이터가 초기화되지 않았습니다.');
      return [];
    }

    final String q = query.trim().toLowerCase();
    final List<Map<String, dynamic>> results = [];

    // KOSPI 검색
    for (final stock in _kospiStocks.values) {
      final name = stock['name'] as String? ?? '';
      final code = stock['code'] as String? ?? '';
      
      if (q.isEmpty || 
          name.toLowerCase().contains(q) || 
          code.contains(q)) {
        results.add(stock);
      }
    }

    // KOSDAQ 검색
    for (final stock in _kosdaqStocks.values) {
      final name = stock['name'] as String? ?? '';
      final code = stock['code'] as String? ?? '';
      
      if (q.isEmpty || 
          name.toLowerCase().contains(q) || 
          code.contains(q)) {
        results.add(stock);
      }
    }

    // NASDAQ 검색
    print('🔍 NASDAQ 종목 검색: "$q" (총 ${_nasdaqStocks.length}개 종목)');
    for (final stock in _nasdaqStocks.values) {
      final name = stock['name'] as String? ?? '';
      final code = stock['code'] as String? ?? '';
      
      if (q.isEmpty || 
          name.toLowerCase().contains(q) || 
          code.toLowerCase().contains(q)) {
        results.add(stock);
        print('  ✅ NASDAQ 매칭: $code - $name');
      }
    }
    
    // NYSE 검색
    print('🔍 NYSE 종목 검색: "$q" (총 ${_nyseStocks.length}개 종목)');
    for (final stock in _nyseStocks.values) {
      final name = stock['name'] as String? ?? '';
      final code = stock['code'] as String? ?? '';
      
      if (q.isEmpty || 
          name.toLowerCase().contains(q) || 
          code.toLowerCase().contains(q)) {
        results.add(stock);
        print('  ✅ NYSE 매칭: $code - $name');
      }
    }

    // 페이징 처리
    final int start = offset.clamp(0, results.length);
    final int end = (start + limit).clamp(0, results.length);
    
    return results.sublist(start, end);
  }

  /// 종목명 조회
  String? getStockName(String stockCode) {
    if (!_isInitialized) return null;
    
    return _kospiStocks[stockCode]?['name'] ?? 
           _kosdaqStocks[stockCode]?['name'] ??
           _nasdaqStocks[stockCode]?['name'] ??
           _nyseStocks[stockCode]?['name'];
  }

  /// 종목 정보 조회
  Map<String, dynamic>? getStockInfo(String stockCode) {
    if (!_isInitialized) return null;
    
    return _kospiStocks[stockCode] ?? _kosdaqStocks[stockCode] ?? _nasdaqStocks[stockCode] ?? _nyseStocks[stockCode];
  }

  /// 모든 종목 코드 반환
  List<String> getAllStockCodes() {
    if (!_isInitialized) return [];
    
    return [..._kospiStocks.keys, ..._kosdaqStocks.keys, ..._nasdaqStocks.keys, ..._nyseStocks.keys];
  }

  /// KOSPI 종목 코드만 반환
  List<String> getKospiStockCodes() {
    if (!_isInitialized) return [];
    
    return _kospiStocks.keys.toList();
  }

  /// KOSDAQ 종목 코드만 반환
  List<String> getKosdaqStockCodes() {
    if (!_isInitialized) return [];
    
    return _kosdaqStocks.keys.toList();
  }

  /// 나스닥 종목 목록 반환
  List<String> getNasdaqStockCodes() {
    if (!_isInitialized) {
      print('⚠️ StockMasterParser가 초기화되지 않았습니다. 강제 초기화 시도...');
      // 강제로 초기화 시도
      initialize();
    }
    
    final codes = _nasdaqStocks.keys.toList();
    if (!_loggedNasdaqSample) {
      print('📊 나스닥 종목 코드 조회: ${codes.length}개');
      if (codes.isNotEmpty) {
        print('📈 나스닥 종목 샘플 (처음 10개):');
        for (int i = 0; i < codes.length && i < 10; i++) {
          final code = codes[i];
          final info = _nasdaqStocks[code];
          final name = info?['name'] ?? 'Unknown';
          print('  $code: $name');
        }
      } else {
        print('⚠️ 나스닥 종목이 없습니다.');
        print('🔍 초기화 상태 확인: $_isInitialized');
        print('🔍 나스닥 데이터 크기: ${_nasdaqStocks.length}');
      }
      _loggedNasdaqSample = true;
    }
    
    return codes;
  }

  /// NYSE 종목 목록 반환
  List<String> getNyseStockCodes() {
    if (!_isInitialized) {
      print('⚠️ StockMasterParser가 초기화되지 않았습니다. 강제 초기화 시도...');
      // 강제로 초기화 시도
      initialize();
    }
    
    final codes = _nyseStocks.keys.toList();
    if (!_loggedNyseSample) {
      print('📊 NYSE 종목 코드 조회: ${codes.length}개');
      if (codes.isNotEmpty) {
        print('📈 NYSE 종목 샘플 (처음 10개):');
        for (int i = 0; i < codes.length && i < 10; i++) {
          final code = codes[i];
          final info = _nyseStocks[code];
          final name = info?['name'] ?? 'Unknown';
          print('  $code: $name');
        }
      } else {
        print('⚠️ NYSE 종목이 없습니다.');
        print('🔍 초기화 상태 확인: $_isInitialized');
        print('🔍 NYSE 데이터 크기: ${_nyseStocks.length}');
      }
      _loggedNyseSample = true;
    }
    
    return codes;
  }



  /// 초기화 완료 여부
  bool get isInitialized => _isInitialized;
}
