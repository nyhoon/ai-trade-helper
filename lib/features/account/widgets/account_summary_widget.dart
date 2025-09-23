import 'package:flutter/material.dart';
import '../../../core/api/kis_unified_api_service.dart';
import '../../../core/utils/formatters.dart';
import '../utils/account_utils.dart';

/// 계좌 요약 정보를 표시하는 위젯
class AccountSummaryWidget extends StatelessWidget {
  final Map<String, dynamic>? accountData;

  const AccountSummaryWidget({
    super.key,
    required this.accountData,
  });

  @override
  Widget build(BuildContext context) {
    if (accountData == null) {
      return _buildLoadingCard();
    }

    return FutureBuilder<Widget>(
      future: _buildAccountSummary(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return snapshot.data!;
        } else {
          return _buildLoadingCard();
        }
      },
    );
  }

  Widget _buildLoadingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '계좌 요약',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }

  Future<Widget> _buildAccountSummary() async {
    // 새로운 통합 데이터 구조 사용
    final domesticTotalAssets = (accountData!['domesticTotalAssets'] as num?)?.toDouble() ?? 0.0;
    final domesticTotalProfit = (accountData!['domesticTotalProfit'] as num?)?.toDouble() ?? 0.0;
    final domesticProfitRate = (accountData!['domesticProfitRate'] as num?)?.toDouble() ?? 0.0;
    final domesticAvailableBalance = (accountData!['domesticAvailableBalance'] as num?)?.toDouble() ?? 0.0;
    
    final overseasTotalAssets = (accountData!['overseasTotalAssets'] as num?)?.toDouble() ?? 0.0;
    final overseasTotalProfit = (accountData!['overseasTotalProfit'] as num?)?.toDouble() ?? 0.0;
    final overseasProfitRate = (accountData!['overseasProfitRate'] as num?)?.toDouble() ?? 0.0;
    final overseasAvailableBalance = (accountData!['overseasAvailableBalance'] as num?)?.toDouble() ?? 0.0;
    
    final domesticHoldings = accountData!['domesticHoldings'] as List<dynamic>? ?? [];
    final overseasHoldings = accountData!['overseasHoldings'] as List<dynamic>? ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '계좌 요약',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            // 국내 계좌 요약
            _buildDomesticAccountSummary(
              domesticTotalAssets,
              domesticTotalProfit,
              domesticProfitRate,
              domesticAvailableBalance,
            ),
            const SizedBox(height: 16),
            // 해외 계좌 요약
            _buildOverseasAccountSummary(
              overseasTotalAssets,
              overseasTotalProfit,
              overseasProfitRate,
              overseasAvailableBalance,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDomesticAccountSummary(
    double totalAssets,
    double totalProfit,
    double profitRate,
    double availableBalance,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.home, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Text(
                '국내 계좌',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  '총 자산',
                  '${_formatNumber(totalAssets)}원',
                  Colors.blue,
                ),
              ),
              Expanded(
                child: _buildSummaryItem(
                  '총 손익',
                  '${totalProfit >= 0 ? '+' : ''}${_formatNumber(totalProfit)}원',
                  totalProfit >= 0 ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  '수익률',
                  '${profitRate >= 0 ? '+' : ''}${profitRate.toStringAsFixed(2)}%',
                  profitRate >= 0 ? Colors.green : Colors.red,
                ),
              ),
              Expanded(
                child: _buildSummaryItem(
                  '주문가능',
                  '${_formatNumber(availableBalance)}원',
                  Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverseasAccountSummary(
    double totalAssets,
    double totalProfit,
    double profitRate,
    double availableBalance,
  ) {
    // 해외 계좌가 없는 경우 (모든 값이 0인 경우)
    final hasOverseasAccount = totalAssets > 0 || totalProfit != 0 || availableBalance > 0;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasOverseasAccount ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasOverseasAccount ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.3)
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasOverseasAccount ? Icons.language : Icons.language_outlined,
                color: hasOverseasAccount ? Colors.green : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '해외 계좌',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: hasOverseasAccount ? Colors.green[700] : Colors.grey[700],
                ),
              ),
              if (!hasOverseasAccount) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '없음',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (hasOverseasAccount) ...[
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    '총 자산(\$)',
                    '\$${totalAssets.toStringAsFixed(2)}',
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    '총 손익(\$)',
                    '${totalProfit >= 0 ? '+' : ''}\$${totalProfit.toStringAsFixed(2)}',
                    totalProfit >= 0 ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    '수익률',
                    '${profitRate >= 0 ? '+' : ''}${profitRate.toStringAsFixed(2)}%',
                    profitRate >= 0 ? Colors.green : Colors.red,
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    '주문가능(\$)',
                    '\$${availableBalance.toStringAsFixed(2)}',
                    Colors.orange,
                  ),
                ),
              ],
            ),
          ] else ...[
            const Center(
              child: Text(
                '해외 계좌가 없습니다',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  /// 숫자를 천 단위 구분으로 포맷팅
  String _formatNumber(dynamic number) {
    return Formatters.formatNumber(number);
  }

}
