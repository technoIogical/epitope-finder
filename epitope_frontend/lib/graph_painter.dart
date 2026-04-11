import 'package:flutter/material.dart';

class GraphRowPainter extends CustomPainter {
  final List<String> columns;
  final Set<String> positiveMatches;
  final Set<String> missingRequired;
  final double cellWidth;
  final Set<String> recipientSet;
  final Set<String> donorSet;
  final double fontSize;
  final ScrollController scrollController;
  final double graphStartX;

  GraphRowPainter({
    required this.columns,
    required this.positiveMatches,
    required this.missingRequired,
    required this.cellWidth,
    required this.recipientSet,
    required this.donorSet,
    required this.fontSize,
    required this.scrollController,
    required this.graphStartX,
  }) : super(repaint: scrollController);

  @override
  void paint(Canvas canvas, Size size) {
    if (!scrollController.hasClients) return;

    final double scrollOffset = scrollController.offset;
    final double viewportStart = scrollOffset - graphStartX;
    final double viewportEnd = viewportStart + size.width;

    int startIdx = (viewportStart / cellWidth).floor().clamp(0, columns.length);
    int endIdx = (viewportEnd / cellWidth).ceil().clamp(0, columns.length);

    final Paint paint = Paint()..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

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

    // Draw horizontal bottom border for the row
    final Paint rowBorderPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      rowBorderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant GraphRowPainter oldDelegate) {
    return oldDelegate.columns != columns ||
        oldDelegate.positiveMatches != positiveMatches ||
        oldDelegate.missingRequired != missingRequired ||
        oldDelegate.cellWidth != cellWidth ||
        oldDelegate.recipientSet != recipientSet ||
        oldDelegate.donorSet != donorSet ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.scrollController != scrollController;
  }
}
