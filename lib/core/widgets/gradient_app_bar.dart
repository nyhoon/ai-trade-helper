import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final dynamic title; // String 또는 Widget 모두 받을 수 있도록
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;
  final Widget? leading;
  final Color? backgroundColor;
  final double elevation;
  final bool centerTitle;
  final PreferredSizeWidget? bottom;
  final List<Color>? colors;

  const GradientAppBar({
    super.key,
    required this.title,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.leading,
    this.backgroundColor,
    this.elevation = 0,
    this.centerTitle = false,
    this.bottom,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final defaultColors = [
      const Color(0xFF4A90E2), // 밝은 파란색
      const Color(0xFF357ABD), // 중간 파란색
      const Color(0xFF2E5A8A), // 진한 파란색
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors ?? defaultColors,
          stops: const [0.0, 0.5, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: AppBar(
        title: title is String 
          ? Text(
              title as String,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            )
          : title,
        actions: actions,
        automaticallyImplyLeading: automaticallyImplyLeading,
        leading: leading,
        backgroundColor: Colors.transparent,
        elevation: elevation,
        centerTitle: centerTitle,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        bottom: bottom,
        // 상태표시줄과 연속되도록 설정
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
    );
  }

  @override
  Size get preferredSize {
    if (bottom != null) {
      return Size.fromHeight(kToolbarHeight + bottom!.preferredSize.height);
    }
    return const Size.fromHeight(kToolbarHeight);
  }
}
