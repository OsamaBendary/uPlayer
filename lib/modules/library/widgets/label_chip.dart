import 'package:flutter/material.dart';

/// Same "text sitting in a black translucent pill" pattern used on the
/// player screen's title/artist labels — reused everywhere text appears
/// on the library screens for a consistent look.
class LabelChip extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;

  const LabelChip(
      this.text, {
        super.key,
        this.style,
        this.maxLines = 1,
        this.textAlign = TextAlign.start,
      });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: style ?? const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}