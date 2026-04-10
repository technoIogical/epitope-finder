import 'package:flutter/material.dart';
import 'dart:math' as math;

class GraphHeaderPainter extends CustomPainter {
  final List<String> columns;
  final Set<String> userAllelesSet;
  final double cellWidth;
  final double fontSize;
  final double scrollOffset;

  GraphHeaderPainter({
    required this.columns,
    required this.userAllelesSet,
    required this.cellWidth,
    required this.fontSize,
    required this.scrollOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double viewportStart = scrollOffset;
    final double viewportEnd = viewportStart + size.width;

    int startIdx = (viewportStart / cellWidth).floor().clamp(0, columns.length);
    int endIdx = (viewportEnd / cellWidth).ceil().clamp(0, columns.length);

    for (int i = startIdx; i < endIdx; i++) {
      String allele = columns[i];
      bool isUserAllele = userAllelesSet.contains(allele);

      final textSpan = TextSpan(
        text: allele,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: isUserAllele ? FontWeight.bold : FontWeight.normal,
          color: isUserAllele ? Colors.black : Colors.grey[700],
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      textPainter.layout();

      // Save canvas state for rotation
      canvas.save();

      // 1. Calculate center of the cell in screen coordinates
      double centerX = (i * cellWidth) + (cellWidth / 2);
      double centerY = size.height / 2;

      // 2. Translate to center
      canvas.translate(centerX, centerY);

      // 3. Rotate 90 degrees counter-clockwise
      canvas.rotate(-math.pi / 2);

      // 4. Paint text centered at the new origin (0,0)
      // After rotation:
      // - text length is along the vertical axis of the screen
      // - text thickness is along the horizontal axis of the screen
      textPainter.paint(
          canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));

      canvas.restore();

      // Draw vertical divider
      final Paint dividerPaint = Paint()
        ..color = Colors.grey.shade300
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset((i + 1) * cellWidth, 0),
        Offset((i + 1) * cellWidth, size.height),
        dividerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GraphHeaderPainter old) {
    return old.columns != columns ||
        old.userAllelesSet != userAllelesSet ||
        old.cellWidth != cellWidth ||
        old.scrollOffset != scrollOffset ||
        old.fontSize != fontSize;
  }
}
