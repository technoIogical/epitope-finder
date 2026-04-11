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

      // --- UPDATED CUSTOM HEX SHADES ---
      final String upper = allele.toUpperCase();
      Color bgColor = Colors.white; 
      
      if (upper.startsWith('A*') || upper.startsWith('A-')) {
        bgColor = const Color(0xFFFEE4CB); // Soft Peach/Orange
      } else if (upper.startsWith('B*') || upper.startsWith('B-')) {
        bgColor = const Color(0xFFEAE4F2); // Soft Lavender/Purple
      } else if (upper.startsWith('C*') || upper.startsWith('C-')) {
        bgColor = const Color(0xFFD6EAF8); // Soft Sky Blue
      } else if (upper.startsWith('DR')) {
        bgColor = const Color(0xFFC0E8E4); // Light Teal
      } else if (upper.startsWith('DQ')) {
        bgColor = const Color(0xFFEAAFAF); // Lighter #c17171 (Muted Rose)
      } else if (upper.startsWith('DP')) {
        bgColor = const Color(0xFFBCBBE0); // Lighter #777696 (Soft Periwinkle)
      }

      // Draw the solid color background
      final Rect cellRect = Rect.fromLTWH(i * cellWidth, 0, cellWidth, size.height);
      final Paint bgPaint = Paint()..color = bgColor;
      canvas.drawRect(cellRect, bgPaint);

      final textSpan = TextSpan(
        text: allele,
        style: TextStyle(
          fontSize: 11 * (fontSize / 12.0),
          fontWeight: FontWeight.w600, 
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