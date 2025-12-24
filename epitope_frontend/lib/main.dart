import 'dart:convert';
import 'package:flutter/gestures.dart'; // Required for mouse scroll
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for keyboard keys
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
  final ScrollController _verticalScrollController = ScrollController(); // Added Vertical Controller

  // Data State
  List<Map<String, dynamic>> _epitopeResults = [];
  List<String> _sortedColumns = []; 
  Set<String> _userAllelesSet = {}; 
  
  bool _isLoading = false;
  String _errorMessage = '';

  final String apiUrl = 'https://epitope-server-998762220496.europe-west1.run.app';

  // --- ZOOM & LAYOUT STATE ---
  double _zoomLevel = 1.0; 
  
  final double baseCellWidth = 28.0; 
  final double baseCellHeight = 28.0; 
  final double baseHeaderHeight = 140.0;

  double get currentCellWidth => baseCellWidth * _zoomLevel;
  double get currentCellHeight => baseCellHeight * _zoomLevel;
  double get currentHeaderHeight => baseHeaderHeight * _zoomLevel;
  double get currentFontSize => 12.0 * _zoomLevel;

  // --- ZOOM LOGIC ---
  void _updateZoom(double change) {
    setState(() {
      _zoomLevel = (_zoomLevel + change).clamp(0.5, 3.0); // Limit zoom between 50% and 300%
    });
  }

  Future<void> fetchData(String inputAlleles) async {
    // ... (Same Fetch Logic as before) ...
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
    // Shortcuts Wrapper handles keyboard events
    return CallbackShortcuts(
      bindings: {
        // Option 1: Ctrl + Equal (= is the plus key)
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () => _updateZoom(0.1),
        const SingleActivator(LogicalKeyboardKey.add, control: true): () => _updateZoom(0.1),
        // Option 2: Ctrl + Minus
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () => _updateZoom(-0.1),
        
        // Option 3: Fallback keys (Alt + Plus/Minus) just in case browser steals Ctrl
        const SingleActivator(LogicalKeyboardKey.equal, alt: true): () => _updateZoom(0.1),
        const SingleActivator(LogicalKeyboardKey.minus, alt: true): () => _updateZoom(-0.1),
      },
      child: Focus(
        autofocus: true, // Allows the widget to capture keys immediately
        child: Scaffold(
          appBar: AppBar(title: Text('HLA Epitope Registry')),
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
                        ? Center(child: Text(_errorMessage, style: TextStyle(color: Colors.red)))
                        : _epitopeResults.isEmpty
                            ? Center(child: Text('Enter alleles to view matrix.'))
                            : _buildMatrixContent(), // Extracted for cleanliness
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Wraps the matrix in a Mouse Listener to handle Ctrl + Scroll
  Widget _buildMatrixContent() {
    const double nameWidth = 100;
    const double countWidth = 50;
    double totalWidth = nameWidth + (countWidth * 2) + (_sortedColumns.length * currentCellWidth);

    return Listener(
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent) {
          // Check if Control key is held down
          if (HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.controlLeft) ||
              HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.controlRight)) {
            
            // Determine direction
            double change = pointerSignal.scrollDelta.dy > 0 ? -0.1 : 0.1;
            _updateZoom(change);
          }
        }
      },
      child: Scrollbar(
        controller: _horizontalScrollController,
        thumbVisibility: true,
        trackVisibility: true,
        thickness: 12,
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
                    controller: _verticalScrollController, // Attach vertical controller
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
          Text("Zoom: ${(_zoomLevel * 100).round()}%", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          SizedBox(width: 8),
          Icon(Icons.zoom_out, size: 20, color: Colors.grey),
          SizedBox(
            width: 200,
            child: Slider(
              value: _zoomLevel,
              min: 0.5,
              max: 3.0, // Increased max zoom
              divisions: 25,
              onChanged: (value) {
                setState(() {
                  _zoomLevel = value;
                });
              },
            ),
          ),
          Icon(Icons.zoom_in, size: 20, color: Colors.grey),
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
                isDense: true, 
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
                       fontWeight: isUserAllele ? FontWeight.bold : FontWeight.normal,
                       color: isUserAllele ? Colors.black : Colors.grey[700],
                     ),
                     overflow: TextOverflow.visible,
                   ),
                 ),
               ),
             );
          }),
        ],
      ),
    );
  }

  Widget _buildHighPerformanceRow(Map<String, dynamic> row, double nameW, double countW) {
    final positiveMatches = Set<String>.from(row['Positive Matches'] ?? []);
    final missingRequired = Set<String>.from(row['Missing Required Alleles'] ?? []);

    return Container(
      height: currentCellHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          _fixedCell(row['Epitope Name'] ?? '', nameW),
          _fixedCell(row['Number of Positive Matches'].toString(), countW),
          _fixedCell(row['Number of Missing Required Alleles'].toString(), countW),
          
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: HeatmapRowPainter(
                columns: _sortedColumns,
                positiveMatches: positiveMatches,
                missingRequired: missingRequired,
                cellWidth: currentCellWidth,
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
      padding: EdgeInsets.symmetric(horizontal: 2),
      decoration: isHeader 
        ? BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300)))
        : null,
      child: Text(
        text,
        style: TextStyle(
          fontWeight: fontWeight ?? (isHeader ? FontWeight.bold : FontWeight.normal),
          color: textColor ?? Colors.black87,
          fontSize: isHeader ? 12 : 11,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

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
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < columns.length; i++) {
      String allele = columns[i];
      
      if (positiveMatches.contains(allele)) {
        paint.color = Colors.green.shade600;
      } else if (missingRequired.contains(allele)) {
        paint.color = Colors.red.shade600;
      } else {
        paint.color = Colors.grey.shade100;
      }

      Rect rect = Rect.fromLTWH(i * cellWidth, 0, cellWidth, size.height);
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant HeatmapRowPainter oldDelegate) {
    return oldDelegate.columns != columns ||
           oldDelegate.positiveMatches != positiveMatches ||
           oldDelegate.missingRequired != missingRequired ||
           oldDelegate.cellWidth != cellWidth;
  }
}