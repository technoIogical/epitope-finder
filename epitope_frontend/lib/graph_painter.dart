import 'package:flutter/material.dart';

class GraphRowPainter extends CustomPainter {
  final List<String> columns;
  final Set<String> positiveMatches;
  final Set<String> missingRequired;
  final double cellWidth;
  final Set<String> recipientSet;
  final Set<String> donorSet;
  final double fontSize;
  final double scrollOffset;
  final double graphStartX;

  GraphRowPainter({
    required this.columns,
    required this.positiveMatches,
    required this.missingRequired,
    required this.cellWidth,
    required this.recipientSet,
    required this.donorSet,
    required this.fontSize,
    required this.scrollOffset,
    required this.graphStartX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Calculate visible range in terms of column indices
    final double viewportStart = scrollOffset - graphStartX;
    final double viewportEnd = viewportStart + size.width;

    int startIdx = (viewportStart / cellWidth).floor().clamp(0, columns.length);
    int endIdx = (viewportEnd / cellWidth).ceil().clamp(0, columns.length);

    for (int i = startIdx; i < endIdx; i++) {
      String allele = columns[i];
      bool isPositive = positiveMatches.contains(allele);
      bool isMissing = missingRequired.contains(allele);
      bool isAlleleInEpitope = isPositive || isMissing;

      if (isPositive) {
        paint.color = Colors.green.shade600;
      } else if (isMissing) {
        paint.color = Colors.red.shade600;
      } else {
        paint.color = Colors.grey.shade100;
      }

      Rect rect = Rect.fromLTWH(i * cellWidth, 0, cellWidth, size.height);
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, borderPaint);

      if (isAlleleInEpitope) {
        String? label;
        if (recipientSet.contains(allele)) {
          label = "S";
        } else if (donorSet.contains(allele)) {
          label = "D";
        }

        if (label != null) {
          final textSpan = TextSpan(
            text: label,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              shadows: const [
                Shadow(
                  offset: Offset(1, 1),
                  blurRadius: 2,
                  color: Colors.black45,
                ),
              ],
            ),
          );
          final textPainter = TextPainter(
            text: textSpan,
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();

          final offset = Offset(
            (i * cellWidth) + (cellWidth - textPainter.width) / 2,
            (size.height - textPainter.height) / 2,
          );
          textPainter.paint(canvas, offset);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant GraphRowPainter old) {
    return old.columns != columns ||
        old.recipientSet != recipientSet ||
        old.donorSet != donorSet ||
        old.cellWidth != cellWidth ||
        old.scrollOffset != scrollOffset ||
        old.fontSize != fontSize;
  }
}
