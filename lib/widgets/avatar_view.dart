import 'dart:io';

import 'package:flutter/material.dart';

class AvatarView extends StatelessWidget {
  const AvatarView({
    super.key,
    this.path,
    required this.name,
    this.size = 40,
    this.borderColor,
  });

  final String? path;
  final String name;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    final hasImage = file != null && file.existsSync();
    final fallbackColor =
        Colors.primaries[name.hashCode.abs() % Colors.primaries.length].shade400;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border:
            borderColor == null ? null : Border.all(color: borderColor!, width: 2),
      ),
      child: hasImage
          ? Image.file(file, width: size, height: size, fit: BoxFit.cover)
          : ColoredBox(
              color: fallbackColor,
              child: Center(
                child: Text(
                  name.isEmpty ? '?' : name.substring(0, 1),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.38,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
    );
  }
}
