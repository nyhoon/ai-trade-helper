import 'package:flutter/material.dart';
import '../../core/trading/watchlist_manager.dart';
import '../../core/data/app_data_manager.dart';

class WatchlistDialog extends StatefulWidget {
  final List<WatchlistItem> watchlist;
  final Function(String) onRemove;
  final VoidCallback onClear;
  final Function(String, String)? onStockSelected; // 종목 선택 콜백 추가

  const WatchlistDialog({
    super.key,
    required this.watchlist,
    required this.onRemove,
    required this.onClear,
    this.onStockSelected,
  });

  @override
  State<WatchlistDialog> createState() => _WatchlistDialogState();
}

class _WatchlistDialogState extends State<WatchlistDialog> {
  List<WatchlistItem> _currentWatchlist = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentWatchlist = List.from(widget.watchlist);
  }

  @override
  void didUpdateWidget(WatchlistDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.watchlist != widget.watchlist) {
      setState(() {
        _currentWatchlist = List.from(widget.watchlist);
      });
    }
  }

  Future<void> _removeFromWatchlist(String stockCode) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 로컬 상태에서 즉시 제거
      setState(() {
        _currentWatchlist.removeWhere((item) => item.stockCode == stockCode);
      });

      // 부모 위젯에 알림
      await widget.onRemove(stockCode);

      // 성공 메시지 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('관심종목에서 제거되었습니다.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // 실패 시 원래 상태로 복원
      setState(() {
        _currentWatchlist = List.from(widget.watchlist);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('제거 실패: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _clearAllWatchlist() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 로컬 상태에서 즉시 제거
      setState(() {
        _currentWatchlist.clear();
      });

      // 부모 위젯에 알림
      widget.onClear();

      // 성공 메시지 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('모든 관심종목이 제거되었습니다.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // 실패 시 원래 상태로 복원
      setState(() {
        _currentWatchlist = List.from(widget.watchlist);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('전체 제거 실패: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onStockTap(WatchlistItem item) {
    // 종목 선택 콜백이 있으면 호출
    if (widget.onStockSelected != null) {
      widget.onStockSelected!(item.stockCode, item.stockName);
    }
    
    // 다이얼로그 닫기
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    
    return Dialog(
      child: Container(
        width: isSmallScreen ? screenSize.width * 0.95 : screenSize.width * 0.8,
        height: isSmallScreen ? screenSize.height * 0.8 : screenSize.height * 0.7,
        constraints: BoxConstraints(
          minWidth: isSmallScreen ? 300 : 400,
          maxWidth: isSmallScreen ? 500 : 800,
          minHeight: isSmallScreen ? 400 : 500,
          maxHeight: isSmallScreen ? 700 : 900,
        ),
        padding: EdgeInsets.all(isSmallScreen ? 16.0 : 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                const Icon(Icons.favorite, color: Colors.red, size: 24),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '관심종목',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_currentWatchlist.isNotEmpty && !_isLoading)
                  IconButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('관심종목 초기화'),
                          content: const Text('모든 관심종목을 삭제하시겠습니까?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('취소'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _clearAllWatchlist();
                              },
                              child: const Text('삭제', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.clear_all, color: Colors.grey),
                    tooltip: '전체 삭제',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 내용
            Expanded(
              child: _currentWatchlist.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.favorite_border, 
                            size: isSmallScreen ? 48 : 64, 
                            color: Colors.grey
                          ),
                          SizedBox(height: isSmallScreen ? 12 : 16),
                          Text(
                            '관심종목이 없습니다',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 14 : 16,
                              color: Colors.grey,
                            ),
                          ),
                          SizedBox(height: isSmallScreen ? 6 : 8),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16 : 24),
                            child: Text(
                              '트레이딩 화면에서 종목을 선택하고\n하트 버튼을 눌러 관심종목에 추가하세요',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isSmallScreen ? 12 : 14,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _currentWatchlist.length,
                      itemBuilder: (context, index) {
                        final item = _currentWatchlist[index];
                        return Card(
                          margin: EdgeInsets.symmetric(
                            vertical: isSmallScreen ? 4 : 6,
                            horizontal: isSmallScreen ? 2 : 4,
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 12 : 16,
                              vertical: isSmallScreen ? 4 : 8,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: Colors.red.shade100,
                              radius: isSmallScreen ? 16 : 20,
                              child: Icon(
                                Icons.favorite, 
                                color: Colors.red, 
                                size: isSmallScreen ? 16 : 20
                              ),
                            ),
                            title: Text(
                              _getDisplayName(item),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: isSmallScreen ? 14 : 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${item.stockCode} • ${_formatDate(item.addedAt)}',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: isSmallScreen ? 12 : 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () => _onStockTap(item),
                                  icon: Icon(
                                    Icons.arrow_forward_ios,
                                    size: isSmallScreen ? 18 : 20,
                                    color: Colors.blue,
                                  ),
                                  tooltip: '거래탭에서 보기',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                IconButton(
                                  onPressed: () => _removeFromWatchlist(item.stockCode),
                                  icon: Icon(
                                    Icons.delete,
                                    size: isSmallScreen ? 18 : 20,
                                    color: Colors.red,
                                  ),
                                  tooltip: '삭제',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                            onTap: () => _onStockTap(item),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}';
  }

  String _getDisplayName(WatchlistItem item) {
    print('🔍 관심종목 다이얼로그 종목명 해결: ${item.stockCode}');
    
    // 1. AppDataManager에서 종목명 가져오기 (실제 데이터)
    final masterName = AppDataManager.instance.getStockName(item.stockCode);
    if (masterName.isNotEmpty && masterName != item.stockCode) {
      print('✅ AppDataManager에서 종목명 찾음: $masterName');
      return '$masterName (${item.stockCode})';
    }
    
    // 2. 저장된 종목명이 유효하면 사용
    if (item.stockName.isNotEmpty && item.stockName != item.stockCode) {
      print('✅ 저장된 종목명 사용: ${item.stockName}');
      return '${item.stockName} (${item.stockCode})';
    }
    
    // 3. 최후 수단으로 종목코드만 반환
    print('⚠️ 종목명을 찾을 수 없어 종목코드 사용: ${item.stockCode}');
    return item.stockCode;
  }
}
