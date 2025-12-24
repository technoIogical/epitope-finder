import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Epitope Matcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: EpitopeMatrixPage(),
    );
  }
}

class EpitopeMatrixPage extends StatefulWidget {
  @override
  _EpitopeMatrixPageState createState() => _EpitopeMatrixPageState();
}

class _EpitopeMatrixPageState extends State<EpitopeMatrixPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _horizontalScrollController = ScrollController();
  
  List<Map<String, dynamic>> _epitopeResults = [];
  List<String> _sortedColumns = []; 
  Set<String> _userAllelesSet = {}; 
  
  bool _isLoading = false;
  String _errorMessage = '';

  final String apiUrl = 'https://epitope-server-998762220496.europe-west1.run.app';

  // UI Constants for CustomPainter
  final double cellWidth = 80.0;
  final double cellHeight = 40.0;

  Future<void> fetchData(String inputAlleles) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _epitopeResults = [];
      _sortedColumns = [];
    });

    if (inputAlleles.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter an allele sequence.';
        _isLoading = false;
      });
      return;
    }

    try {
      final List<String> parsedInput = inputAlleles.split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'input_alleles': parsedInput}),
      );

      if (response.statusCode == 200) {
        final List<dynamic> rawRows = jsonDecode(response.body);
        
        // 1. FILTER: Only show rows with matches
        List<Map<String, dynamic>> processedRows = rawRows
            .map((e) => e as Map<String, dynamic>)
            .where((row) {
              final count = row['Number of Positive Matches'] as int? ?? 0;
              return count > 0;
            })
            .toList();

        if (processedRows.isEmpty) {
           setState(() {
            _isLoading = false;
            _errorMessage = "No compatible epitopes found (0 matches).";
          });
          return;
        }

        // 2. SORT COLUMNS
        List<String> positiveCols = List.from(parsedInput)..sort();
        _userAllelesSet = parsedInput.toSet();

        Set<String> negativeColSet = {};
        for (var row in processedRows) {
          final missing = List<String>.from(row['Missing Required Alleles'] ?? []);
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
    const double nameWidth = 120;
    const double countWidth = 60;
    
    // Total width is fixed columns + dynamic heatmap width
    double totalWidth = nameWidth + (countWidth * 2) + (_sortedColumns.length * cellWidth);

    return Scaffold(
      appBar: AppBar(title: Text('HLA Epitope Registry')),
      body: Column(
        children: [
          _buildSearchHeader(),
          if (_epitopeResults.isNotEmpty) _buildLegend(),
          Divider(height: 1),
          
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(child: Text(_errorMessage, style: TextStyle(color: Colors.red)))
                    : _epitopeResults.isEmpty
                        ? Center(child: Text('Enter alleles to view matrix.'))
                        : Scrollbar(
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
                                        itemCount: _epitopeResults.length,
                                        // "itemExtent" forces fixed height, greatly improving scrolling performance
                                        itemExtent: cellHeight, 
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
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: EdgeInsets.all(16.0),
      color: Colors.grey[100],
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Patient Alleles',
                hintText: 'e.g. A*01:01, B*08:01',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => fetchData(_controller.text),
            icon: Icon(Icons.search),
            label: Text('Analyze'),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          _legendItem(Colors.green.shade400, "Positive Match"),
          SizedBox(width: 16),
          _legendItem(Colors.red.shade400, "Missing Required"),
          SizedBox(width: 16),
          _legendItem(Colors.grey.shade100, "Not Relevant"),
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

  Widget _buildHeaderRow(double nameW, double countW) {
    return Container(
      height: 50,
      color: Colors.grey[200],
      child: Row(
        children: [
          _fixedCell('Epitope', nameW, isHeader: true),
          _fixedCell('Pos (+)', countW, isHeader: true, textColor: Colors.green),
          _fixedCell('Neg (-)', countW, isHeader: true, textColor: Colors.red),
          // Dynamic Headers
          ..._sortedColumns.map((allele) {
             bool isUserAllele = _userAllelesSet.contains(allele);
             return _fixedCell(
               allele, 
               cellWidth, 
               isHeader: true, 
               textColor: isUserAllele ? Colors.black : Colors.grey[700],
               fontWeight: isUserAllele ? FontWeight.bold : FontWeight.normal
             );
          }),
        ],
      ),
    );
  }

  // --- THE OPTIMIZATION IS HERE ---
  Widget _buildHighPerformanceRow(Map<String, dynamic> row, double nameW, double countW) {
    // We still use standard widgets for the text on the left (Name, Counts)
    // But we use ONE CustomPaint widget for the entire strip of colored boxes on the right.
    
    final positiveMatches = Set<String>.from(row['Positive Matches'] ?? []);
    final missingRequired = Set<String>.from(row['Missing Required Alleles'] ?? []);

    return Container(
      height: cellHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          _fixedCell(row['Epitope Name'] ?? '', nameW),
          _fixedCell(row['Number of Positive Matches'].toString(), countW),
          _fixedCell(row['Number of Missing Required Alleles'].toString(), countW),
          
          // This Widget replaces the list of 50+ Containers
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: HeatmapRowPainter(
                columns: _sortedColumns,
                positiveMatches: positiveMatches,
                missingRequired: missingRequired,
                cellWidth: cellWidth,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fixedCell(String text, double width, {bool isHeader = false, Color? textColor, FontWeight? fontWeight}) {
    return Container(
      width: width,
      alignment: Alignment.center,
      decoration: isHeader 
        ? BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300)))
        : null,
      child: Text(
        text,
        style: TextStyle(
          fontWeight: fontWeight ?? (isHeader ? FontWeight.bold : FontWeight.normal),
          color: textColor ?? Colors.black87,
          fontSize: 13,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// --- CUSTOM PAINTER CLASS ---
// This draws directly to the canvas, bypassing the Widget tree overhead.
class HeatmapRowPainter extends CustomPainter {
  final List<String> columns;
  final Set<String> positiveMatches;
  final Set<String> missingRequired;
  final double cellWidth;

  HeatmapRowPainter({
    required this.columns,
    required this.positiveMatches,
    required this.missingRequired,
    required this.cellWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < columns.length; i++) {
      String allele = columns[i];
      
      // Determine color
      if (positiveMatches.contains(allele)) {
        paint.color = Colors.green.shade400;
      } else if (missingRequired.contains(allele)) {
        paint.color = Colors.red.shade400;
      } else {
        paint.color = Colors.grey.shade100;
      }

      // Define the rectangle for this cell
      Rect rect = Rect.fromLTWH(i * cellWidth, 0, cellWidth, size.height);
      
      // Draw Fill
      canvas.drawRect(rect, paint);
      
      // Draw Border (Grid line)
      canvas.drawRect(rect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant HeatmapRowPainter oldDelegate) {
    // Only repaint if the data changes
    return oldDelegate.columns != columns ||
           oldDelegate.positiveMatches != positiveMatches ||
           oldDelegate.missingRequired != missingRequired;
  }
}