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

      // --- THE MISSING GRADIENT LOGIC ---
      final String upper = allele.toUpperCase();
      List<Color> colors = [Colors.white, Colors.white]; 
      
      if (upper.startsWith('A*') || upper.startsWith('A-')) {
        colors = [Colors.orange.shade300, Colors.amber.shade100];
      } else if (upper.startsWith('B*') || upper.startsWith('B-')) {
        colors = [Colors.purple.shade300, Colors.pink.shade100];
      } else if (upper.startsWith('C*') || upper.startsWith('C-')) {
        colors = [Colors.blue.shade400, Colors.lightBlue.shade100];
      } else if (upper.startsWith('DR')) {
        colors = [Colors.teal.shade300, Colors.cyan.shade100];
      } else if (upper.startsWith('DQ')) {
        colors = [Colors.green.shade400, Colors.lightGreen.shade100];
      } else if (upper.startsWith('DP')) {
        colors = [Colors.indigo.shade300, Colors.indigo.shade100];
      }

      // Draw the gradient background if it matches a class
      if (colors.first != Colors.white) {
        final Rect cellRect = Rect.fromLTWH(i * cellWidth, 0, cellWidth, size.height);
        final Paint bgPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ).createShader(cellRect);
        canvas.drawRect(cellRect, bgPaint);
      }

      // Draw the Text (Thickened slightly for contrast over the new gradients)
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