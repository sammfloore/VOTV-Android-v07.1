import 'package:flutter/material.dart';

class AvoTvLogo extends StatelessWidget {
  const AvoTvLogo({
    super.key,
    this.size = 48,
    this.showName = true,
    this.nameSize = 22,
  });

  final double size;
  final bool showName;
  final double nameSize;

  @override
  Widget build(BuildContext context) {
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/branding/avo_tv_logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    );
    if (!showName) return logo;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        SizedBox(width: size * 0.22),
        Text(
          'AVO TV',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: nameSize,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}
