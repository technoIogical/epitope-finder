import 'package:flutter/material.dart';
import 'dart:math' as math;

class GraphHeaderPainter extends CustomPainter {
  final List<String> columns;
  final Set<String> userAllelesSet;
  final double cellWidth;
  final double fontSize;
  final ScrollController scrollController;

  GraphHeaderPainter({
    required this.columns,
    required this.userAllelesSet,
    required this.cellWidth,
    required this.fontSize,
    required this.scrollController,
  }) : super(repaint: scrollController);

  @override
  void paint(Canvas canvas, Size size) {
    if (!scrollController.hasClients) return;

    final double scrollOffset = scrollController.offset;
    final double viewportStart = scrollOffset;
    final double viewportEnd = viewportStart + size.width;

    int startIdx = (viewportStart / cellWidth).floor().clamp(0, columns.length);
    int endIdx = (viewportEnd / cellWidth).ceil().clamp(0, columns.length);

    for (int i = startIdx; i < endIdx; i++) {
      String allele = columns[i];

      final textSpan = TextSpan(
        text: allele,
        style: TextStyle(
          fontSize: 11 * (fontSize / 12.0),
          fontWeight: FontWeight.normal,
          color: Colors.black87,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      textPainter.layout();

      canvas.save();

      double centerX = (i * cellWidth) + (cellWidth / 2);
      double centerY = size.height / 2;

      canvas.translate(centerX, centerY);
      canvas.rotate(-math.pi / 2);

      textPainter.paint(
          canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));

      canvas.restore();

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
  bool shouldRepaint(covariant GraphHeaderPainter oldDelegate) {
    return oldDelegate.columns != columns ||
        oldDelegate.userAllelesSet != userAllelesSet ||
        oldDelegate.cellWidth != cellWidth ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.scrollController != scrollController;
  }
}
