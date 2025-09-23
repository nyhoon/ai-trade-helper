import 'package:flutter/material.dart';

class InvestmentStyleInfo extends StatelessWidget {
  final String styleName;
  final Color styleColor;
  final IconData styleIcon;

  const InvestmentStyleInfo({
    super.key,
    required this.styleName,
    required this.styleColor,
    required this.styleIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: styleColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: styleColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(styleIcon, color: styleColor, size: 14),
          const SizedBox(width: 4),
          Text(
            styleName,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: styleColor),
          ),
        ],
      ),
    );
  }
}


