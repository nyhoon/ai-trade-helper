import 'package:flutter/material.dart';
import '../../core/data/app_data_manager.dart';

class StockSelectionDialog extends StatefulWidget {
  final Function(String, String)? onStockSelected;
  
  const StockSelectionDialog({
    super.key,
    this.onStockSelected,
  });

  @override
  State<StockSelectionDialog> createState() => _StockSelectionDialogState();
}

class _StockSelectionDialogState extends State<StockSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() async {
    final query = _searchController.text.trim();
    
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print('🔍 AppDataManager에서 종목 검색: "$query"');
      
      // AppDataManager에서 종목 검색
      final results = await AppDataManager.instance.searchStocks(query);
      
      // 시장별 종목 개수 확인
      final marketCounts = <String, int>{};
      for (final result in results) {
        final market = result['market'] as String? ?? 'UNKNOWN';
        marketCounts[market] = (marketCounts[market] ?? 0) + 1;
      }
      print('📊 검색 결과 시장별 분포: $marketCounts');
      

      
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
      
      print('✅ 종목 검색 완료: ${results.length}개');
      
    } catch (e) {
      print('❌ 종목 검색 실패: $e');
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    // 데이터베이스 기반이므로 페이징이 필요 없음
    return;
  }

  bool _hasHangul(String s) => RegExp(r'[가-힣]').hasMatch(s);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 헤더
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '종목 선택',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // 검색창
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '종목명 또는 종목코드로 검색',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              textInputAction: TextInputAction.search,
            ),
            
            const SizedBox(height: 16),
            
            // 검색 결과
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _searchResults.isEmpty
                      ? Center(
                          child: Text(
                            _searchController.text.isEmpty
                                ? '종목명 또는 종목코드를 입력하세요'
                                : '검색 결과가 없습니다',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final stock = _searchResults[index];
                            final stockCode = stock['stockCode'] as String? ?? '';
                            final stockName = stock['stockName'] as String? ?? '';
                            final market = stock['market'] as String? ?? '';

                            // null이나 빈 값이면 건너뛰기
                            if (stockCode.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            
                            // 종목명이 있으면 종목명, 없으면 종목코드 표시
                            final String displayName = stockName.isNotEmpty ? stockName : stockCode;
                            
                            final bool isKospi = market.toUpperCase() == 'KOSPI';
                            final bool isKosdaq = market.toUpperCase() == 'KOSDAQ';
                            final bool isNasdaq = market.toUpperCase() == 'NASDAQ';
                            
                            Color chipColor;
                            Color chipText;
                            String marketText;
                            
                            if (isKospi) {
                              chipColor = Colors.blue.shade50;
                              chipText = Colors.blue;
                              marketText = 'KOSPI';
                            } else if (isKosdaq) {
                              chipColor = Colors.green.shade50;
                              chipText = Colors.green;
                              marketText = 'KOSDAQ';
                            } else if (isNasdaq) {
                              chipColor = Colors.orange.shade50;
                              chipText = Colors.orange;
                              marketText = 'NASDAQ';
                            } else {
                              chipColor = Colors.grey.shade50;
                              chipText = Colors.grey;
                              marketText = market.toUpperCase();
                            }

                            return ListTile(
                              title: Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Row(
                                children: [
                                  Text(
                                    stockCode,
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: chipColor,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      marketText,
                                      style: TextStyle(color: chipText, fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (isNasdaq) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'USD',
                                        style: TextStyle(color: Colors.orange.shade700, fontSize: 10, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () {
                                if (widget.onStockSelected != null) {
                                  widget.onStockSelected!(stockCode, stockName);
                                }
                                Navigator.of(context).pop();
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
