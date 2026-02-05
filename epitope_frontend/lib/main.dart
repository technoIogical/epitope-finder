import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Epitope Finder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: EpitopeMatrixPage(),
    );
  }
}

class EpitopeMatrixPage extends StatefulWidget {
  const EpitopeMatrixPage({super.key});

  @override
  _EpitopeMatrixPageState createState() => _EpitopeMatrixPageState();
}

class _EpitopeMatrixPageState extends State<EpitopeMatrixPage> {
  final TextEditingController _antibodyController = TextEditingController();
  final TextEditingController _recipientHlaController = TextEditingController();
  final TextEditingController _donorHlaController = TextEditingController();

  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  List<Map<String, dynamic>> _epitopeResults = [];
  List<String> _sortedColumns = [];
  Set<String> _userAllelesSet = {};

  Set<String> _recipientHlaSet = {};
  Set<String> _donorHlaSet = {};

  bool _isLoading = false;
  String _errorMessage = '';

  // Use the updated server URL
  final String apiUrl = 'https://epitope-server-998762220496.us-west1.run.app';

  double _zoomLevel = 1.0;
  final double baseCellWidth = 28.0;
  final double baseCellHeight = 28.0;
  final double baseHeaderHeight = 140.0;

  double get currentCellWidth => baseCellWidth * _zoomLevel;
  double get currentCellHeight => baseCellHeight * _zoomLevel;
  double get currentHeaderHeight => baseHeaderHeight * _zoomLevel;
  double get currentFontSize => 12.0 * _zoomLevel;

  void _updateZoom(double change) {
    setState(() {
      _zoomLevel = (_zoomLevel + change).clamp(0.5, 3.0);
    });
  }

  List<String> _parseInput(String input) {
    return input
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> fetchData() async {
    String antibodyInput = _antibodyController.text;
    String recipientInput = _recipientHlaController.text;
    String donorInput = _donorHlaController.text;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _epitopeResults = [];
      _sortedColumns = [];
      _recipientHlaSet = _parseInput(recipientInput).toSet();
      _donorHlaSet = _parseInput(donorInput).toSet();
    });

    if (antibodyInput.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter Recipient Antibodies.';
        _isLoading = false;
      });
      return;
    }

    try {
      final List<String> parsedAntibodies = _parseInput(antibodyInput);
      final List<String> parsedRecipientHla = _parseInput(recipientInput);

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer PASTE_YOUR_LONG_TOKEN_HERE',
        },
        body: jsonEncode({
          'input_alleles': parsedAntibodies,
          'recipient_hla': parsedRecipientHla,
        }),
      );

      if (response.statusCode == 200) {
        final List<dynamic> rawRows = jsonDecode(response.body);

        List<Map<String, dynamic>> processedRows =
            rawRows.map((e) => e as Map<String, dynamic>).toList();

        if (processedRows.isEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage = "No antibody matches found.";
          });
          return;
        }

        List<String> positiveCols = List.from(parsedAntibodies)..sort();
        _userAllelesSet = parsedAntibodies.toSet();

        Set<String> negativeColSet = {};
        for (var row in processedRows) {
          final missing = List<String>.from(
            row['Missing Required Alleles'] ?? [],
          );
          negativeColSet.addAll(missing);
        }

        negativeColSet.removeAll(_userAllelesSet);
        List<String> negativeCols = negativeColSet.toList()..sort();

        setState(() {
          _epitopeResults = processedRows;
          _sortedColumns = [...positiveCols, ...negativeCols];
        });
      } else {
        setState(() {
          _errorMessage = 'Server Error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
            _updateZoom(0.1),
        const SingleActivator(LogicalKeyboardKey.add, control: true): () =>
            _updateZoom(0.1),
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
            _updateZoom(-0.1),
        const SingleActivator(LogicalKeyboardKey.equal, alt: true): () =>
            _updateZoom(0.1),
        const SingleActivator(LogicalKeyboardKey.minus, alt: true): () =>
            _updateZoom(-0.1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: Text('Epitope Finder'),
          ),
          body: Column(
            children: [
              _buildSearchHeader(),
              if (_epitopeResults.isNotEmpty) ...[
                _buildLegend(),
                _buildZoomControl(),
                Divider(height: 1),
              ],
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator())
                    : _errorMessage.isNotEmpty
                        ? Center(
                            child: Text(
                              _errorMessage,
                              style: TextStyle(color: Colors.red),
                            ),
                          )
                        : _epitopeResults.isEmpty
                            ? Center(
                                child: Text('Enter antibodies to view matrix.'))
                            : _buildMatrixContent(),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Created By: ',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                    InkWell(
                      onTap: () {
                        launchUrl(Uri.parse(
                            "https://www.linkedin.com/in/rodin-hooshiyar-07036a3a0/"));
                      },
                      child: Text(
                        'Rodin Hooshiyar',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.blue.withValues(alpha: 0.8),
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.blue.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    Text(
                      ' and ',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                    InkWell(
                      onTap: () {
                        launchUrl(Uri.parse(
                            "https://www.linkedin.com/in/manxuan-michael-zhang-014b29237/"));
                      },
                      child: Text(
                        'Manxuan Zhang',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.blue.withValues(alpha: 0.8),
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.blue.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: EdgeInsets.all(16.0),
      color: Colors.grey[100],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              children: [
                TextField(
                  controller: _antibodyController,
                  decoration: InputDecoration(
                    labelText: 'Recipient Antibodies',
                    hintText: 'e.g. A*01:01, B*08:01',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _recipientHlaController,
                  decoration: InputDecoration(
                    labelText: 'Recipient Typing',
                    hintText: 'e.g. A*02:01',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.blue[50],
                    isDense: true,
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _donorHlaController,
                  decoration: InputDecoration(
                    labelText: 'Donor Typing',
                    hintText: 'e.g. B*44:02',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.orange[50],
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            height: 160,
            child: ElevatedButton.icon(
              onPressed: () => fetchData(),
              icon: Icon(Icons.search),
              label: Text('Analyze'),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          Text("Key: "),
          _legendItem(Colors.green.shade600, "Positive Match"),
          _legendItem(Colors.red.shade600, "Missing Required"),
          Row(
            children: [
              Text("S ", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("= Self Antibody"),
            ],
          ),
          Row(
            children: [
              Text("D ", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("= DSA"),
            ],
          ),
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                color: Colors.pink[100],
                child: Center(
                  child: Text("Name", style: TextStyle(fontSize: 8)),
                ),
              ),
              SizedBox(width: 4),
              Text("= Highlighted (Row has Self or DSA)"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(
      children: [
        Container(width: 12, height: 12, color: color),
        SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildMatrixContent() {
    const double nameWidth = 100;
    const double countWidth = 50;
    double totalWidth = nameWidth +
        (countWidth * 2) +
        (_sortedColumns.length * currentCellWidth);

    return Scrollbar(
      controller: _horizontalScrollController,
      thumbVisibility: true,
      trackVisibility: true,
      child: SingleChildScrollView(
        controller: _horizontalScrollController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalWidth,
          child: Column(
            children: [
              _buildHeaderRow(nameWidth, countWidth),
              Expanded(
                child: ListView.builder(
                  controller: _verticalScrollController,
                  padding: EdgeInsets.only(bottom: 15.0),
                  itemCount: _epitopeResults.length,
                  itemExtent: currentCellHeight,
                  itemBuilder: (context, index) {
                    return _buildHighPerformanceRow(
                      _epitopeResults[index],
                      nameWidth,
                      countWidth,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderRow(double nameW, double countW) {
    return Container(
      height: currentHeaderHeight,
      color: Colors.grey[200],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _fixedCell('Epitope', nameW, isHeader: true),
          _fixedCell('Pos', countW, isHeader: true, textColor: Colors.green),
          _fixedCell('Neg', countW, isHeader: true, textColor: Colors.red),
          ..._sortedColumns.map((allele) {
            bool isUserAllele = _userAllelesSet.contains(allele);
            return Container(
              width: currentCellWidth,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: Colors.grey.shade300)),
              ),
              child: RotatedBox(
                quarterTurns: 3,
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    allele,
                    style: TextStyle(
                      fontSize: currentFontSize,
                      fontWeight:
                          isUserAllele ? FontWeight.bold : FontWeight.normal,
                      color: isUserAllele ? Colors.black : Colors.grey[700],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHighPerformanceRow(
    Map<String, dynamic> row,
    double nameW,
    double countW,
  ) {
    final positiveMatches = Set<String>.from(row['Positive Matches'] ?? []);
    final missingRequired = Set<String>.from(
      row['Missing Required Alleles'] ?? [],
    );
    final allAlleles = List<String>.from(row['All_Epitope_Alleles'] ?? []);

    bool hasS = false;
    bool hasD = false;

    for (String allele in allAlleles) {
      if (_recipientHlaSet.contains(allele)) hasS = true;
      if (_donorHlaSet.contains(allele)) hasD = true;
    }

    bool highlightRow = hasS || hasD;
    Color nameBgColor = highlightRow ? Colors.pink.shade100 : Colors.white;

    return Container(
      height: currentCellHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          _fixedCell(row['Epitope Name'] ?? '', nameW, bgColor: nameBgColor),
          _fixedCell(row['Number of Positive Matches'].toString(), countW),
          _fixedCell(
            row['Number of Missing Required Alleles'].toString(),
            countW,
          ),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: HeatmapRowPainter(
                columns: _sortedColumns,
                positiveMatches: positiveMatches,
                missingRequired: missingRequired,
                cellWidth: currentCellWidth,
                recipientSet: _recipientHlaSet,
                donorSet: _donorHlaSet,
                fontSize: currentFontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fixedCell(
    String text,
    double width, {
    bool isHeader = false,
    Color? textColor,
    Color? bgColor,
  }) {
    return Container(
      width: width,
      alignment: Alignment.center,
      color: bgColor,
      padding: EdgeInsets.symmetric(horizontal: 2),
      decoration: isHeader
          ? BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey.shade300)),
            )
          : null,
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: textColor ?? Colors.black87,
          fontSize: isHeader ? 12 : 11,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildZoomControl() {
    return Container(
      color: Colors.grey[50],
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            "Zoom: ${(_zoomLevel * 100).round()}%",
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.zoom_out, size: 20, color: Colors.grey),
            onPressed: () => _updateZoom(-0.1),
          ),
          SizedBox(
            width: 200,
            child: Slider(
              value: _zoomLevel,
              min: 0.5,
              max: 3.0,
              divisions: 25,
              onChanged: (value) => setState(() => _zoomLevel = value),
            ),
          ),
          IconButton(
            icon: Icon(Icons.zoom_in, size: 20, color: Colors.grey),
            onPressed: () => _updateZoom(0.1),
          ),
        ],
      ),
    );
  }
}

class HeatmapRowPainter extends CustomPainter {
  final List<String> columns;
  final Set<String> positiveMatches;
  final Set<String> missingRequired;
  final double cellWidth;
  final Set<String> recipientSet;
  final Set<String> donorSet;
  final double fontSize;

  HeatmapRowPainter({
    required this.columns,
    required this.positiveMatches,
    required this.missingRequired,
    required this.cellWidth,
    required this.recipientSet,
    required this.donorSet,
    required this.fontSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < columns.length; i++) {
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
              shadows: [
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
  bool shouldRepaint(covariant HeatmapRowPainter old) {
    return old.columns != columns ||
        old.recipientSet != recipientSet ||
        old.donorSet != donorSet ||
        old.cellWidth != cellWidth;
  }
}
