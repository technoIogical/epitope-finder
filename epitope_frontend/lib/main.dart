import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'allele_input.dart';

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
  State<EpitopeMatrixPage> createState() => _EpitopeMatrixPageState();
}

class _EpitopeMatrixPageState extends State<EpitopeMatrixPage> {
  final String _appVersion =
      const String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  // Allele Autocomplete Data
  List<String> _allAlleles = [];
  bool _isAlleleFetchError = false;

  final List<String> _selectedAntibodies = [];
  final List<String> _selectedRecipientHla = [];
  final List<String> _selectedDonorHla = [];

  final FocusNode _antibodyFocusNode = FocusNode();
  bool _isWarmedUp = false;
  bool _isWarming = false;

  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _stickyVerticalScrollController = ScrollController();

  List<Map<String, dynamic>> _epitopeResults = [];
  List<String> _sortedColumns = [];
  Set<String> _userAllelesSet = {};

  Set<String> _recipientHlaSet = {};
  Set<String> _donorHlaSet = {};

  bool _isLoading = false;
  String _errorMessage = '';

  // Use the updated server URL
  final String apiUrl = 'https://api.epitopefinder.dpdns.org';

  final ValueNotifier<double> _zoomLevel = ValueNotifier<double>(1.0);
  final double baseCellWidth = 28.0;
  final double baseCellHeight = 28.0;
  final double baseHeaderHeight = 140.0;

  double get currentCellWidth => baseCellWidth * _zoomLevel.value;
  double get currentCellHeight => baseCellHeight * _zoomLevel.value;
  double get currentHeaderHeight => baseHeaderHeight * _zoomLevel.value;
  double get currentFontSize => 12.0 * _zoomLevel.value;

  // Added for sorting
  String? _sortColumn;
  bool _sortAscending = true;

  void _updateZoom(double change) {
    _zoomLevel.value = (_zoomLevel.value + change).clamp(0.5, 3.0);
  }

  @override
  void initState() {
    super.initState();
    _antibodyFocusNode.addListener(_onAntibodyFocusChange);
    _fetchAlleles();

    // Sync vertical scroll controllers
    _verticalScrollController.addListener(() {
      if (_stickyVerticalScrollController.hasClients &&
          _stickyVerticalScrollController.offset !=
              _verticalScrollController.offset) {
        _stickyVerticalScrollController
            .jumpTo(_verticalScrollController.offset);
      }
    });
    _stickyVerticalScrollController.addListener(() {
      if (_verticalScrollController.hasClients &&
          _verticalScrollController.offset !=
              _stickyVerticalScrollController.offset) {
        _verticalScrollController
            .jumpTo(_stickyVerticalScrollController.offset);
      }
    });
  }

  @override
  void dispose() {
    _antibodyFocusNode.removeListener(_onAntibodyFocusChange);
    _antibodyFocusNode.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _stickyVerticalScrollController.dispose();
    super.dispose();
  }

  void _onAntibodyFocusChange() {
    if (_antibodyFocusNode.hasFocus && !_isWarmedUp) {
      _preWarmBackend();
    }
  }

  Future<void> _fetchAlleles() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/alleles'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _allAlleles = data.cast<String>();
          _isAlleleFetchError = false;
        });
      } else {
        setState(() {
          _isAlleleFetchError = true;
        });
      }
    } catch (e) {
      debugPrint('Error fetching alleles: $e');
      setState(() {
        _isAlleleFetchError = true;
      });
    }
  }

  Future<void> _preWarmBackend() async {
    if (_isWarmedUp) return;
    _isWarmedUp = true;
    if (mounted) {
      setState(() {
        _isWarming = true;
      });
    }
    try {
      await http
          .get(Uri.parse('$apiUrl/warmup'))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Pre-warm failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isWarming = false;
        });
      }
    }
  }

  Future<void> fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _epitopeResults = [];
      _sortedColumns = [];
      _recipientHlaSet = _selectedRecipientHla.toSet();
      _donorHlaSet = _selectedDonorHla.toSet();
    });

    if (_selectedAntibodies.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter Recipient Antibodies.';
        _isLoading = false;
      });
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer PASTE_YOUR_LONG_TOKEN_HERE',
        },
        body: jsonEncode({
          'input_alleles': _selectedAntibodies,
          'recipient_hla': _selectedRecipientHla,
        }),
      );

      if (response.statusCode == 200) {
        final List<dynamic> rawRows = jsonDecode(response.body);

        List<Map<String, dynamic>> rawProcessedRows =
            rawRows.map((e) => e as Map<String, dynamic>).toList();

        if (rawProcessedRows.isEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage = "No antibody matches found.";
          });
          return;
        }

        List<String> positiveCols = List.from(_selectedAntibodies)..sort();
        _userAllelesSet = _selectedAntibodies.toSet();

        Set<String> negativeColSet = {};
        List<Map<String, dynamic>> processedRows = [];

        for (var row in rawProcessedRows) {
          final missing = List<String>.from(
            row['Missing Required Alleles'] ?? [],
          );
          negativeColSet.addAll(missing);

          // Pre-calculate flags
          final allAlleles =
              List<String>.from(row['All_Epitope_Alleles'] ?? []);
          bool hasS = false;
          bool hasD = false;

          for (String allele in allAlleles) {
            if (_recipientHlaSet.contains(allele)) hasS = true;
            if (_donorHlaSet.contains(allele)) hasD = true;
          }

          processedRows.add({
            ...row,
            'cached_hasS': hasS,
            'cached_hasD': hasD,
            'cached_highlightRow': hasS || hasD,
            'cached_positiveMatchesSet':
                Set<String>.from(row['Positive Matches'] ?? []),
            'cached_missingRequiredSet': Set<String>.from(missing),
          });
        }

        negativeColSet.removeAll(_userAllelesSet);
        List<String> negativeCols = negativeColSet.toList()..sort();

        setState(() {
          _epitopeResults = processedRows;
          _sortedColumns = [...positiveCols, ...negativeCols];
          _sortColumn = null;
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

  void _sortResults(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }

      _epitopeResults.sort((a, b) {
        dynamic valA = a[column];
        dynamic valB = b[column];
        int cmp;
        if (valA is num && valB is num) {
          cmp = valA.compareTo(valB);
        } else {
          cmp = valA.toString().compareTo(valB.toString());
        }
        return _sortAscending ? cmp : -cmp;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _zoomLevel,
      builder: (context, zoom, child) {
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.equal, control: true):
                () => _updateZoom(0.1),
            const SingleActivator(LogicalKeyboardKey.add, control: true): () =>
                _updateZoom(0.1),
            const SingleActivator(LogicalKeyboardKey.minus, control: true):
                () => _updateZoom(-0.1),
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
                                    child: Text(
                                        'Enter antibodies to view matrix.'))
                                : _buildMatrixContent(),
                  ),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        );
      },
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isAlleleFetchError)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'Warning: Could not load autocomplete data.',
                      style: TextStyle(color: Colors.red[700], fontSize: 12),
                    ),
                  ),
                AlleleInput(
                  label: 'Recipient Antibodies',
                  hintText: 'e.g. A*01:01, B*08:01',
                  selectedAlleles: _selectedAntibodies,
                  allAlleles: _allAlleles,
                  onChanged: () => setState(() {}),
                  isWarming: _isWarming,
                  focusNode: _antibodyFocusNode,
                ),
                const SizedBox(height: 8),
                AlleleInput(
                  label: 'Recipient Typing',
                  hintText: 'e.g. A*02:01',
                  selectedAlleles: _selectedRecipientHla,
                  allAlleles: _allAlleles,
                  onChanged: () => setState(() {}),
                  fillColor: Colors.blue[50],
                ),
                const SizedBox(height: 8),
                AlleleInput(
                  label: 'Donor Typing',
                  hintText: 'e.g. B*44:02',
                  selectedAlleles: _selectedDonorHla,
                  allAlleles: _allAlleles,
                  onChanged: () => setState(() {}),
                  fillColor: Colors.orange[50],
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            height: 200, // Adjusted for AlleleInput height
            child: ElevatedButton.icon(
              onPressed: fetchData,
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
    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Matrix Legend",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          SizedBox(height: 8),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _legendItem(Colors.green.shade600, "Positive Match"),
              _legendItem(Colors.red.shade600, "Missing Required"),
              _legendItem(Colors.pink.shade100, "Self/DSA Highlight"),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("S",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900)),
                  SizedBox(width: 4),
                  Text("= Self HLA", style: TextStyle(fontSize: 12)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("D",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900)),
                  SizedBox(width: 4),
                  Text("= DSA", style: TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
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
    final double stickyTotalWidth = nameWidth + (countWidth * 2);

    return Row(
      children: [
        // Sticky Columns
        SizedBox(
          width: stickyTotalWidth,
          child: Column(
            children: [
              _buildStickyHeader(nameWidth, countWidth),
              Expanded(
                child: ListView.builder(
                  controller: _stickyVerticalScrollController,
                  padding: EdgeInsets.only(bottom: 15.0),
                  itemCount: _epitopeResults.length,
                  itemExtent: currentCellHeight,
                  itemBuilder: (context, index) {
                    final row = _epitopeResults[index];
                    final bool highlightRow =
                        row['cached_highlightRow'] ?? false;
                    final Color nameBgColor =
                        highlightRow ? Colors.pink.shade100 : Colors.white;
                    return Container(
                      height: currentCellHeight,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                            bottom: BorderSide(color: Colors.grey.shade300)),
                      ),
                      child: Row(
                        children: [
                          _fixedCell(row['Epitope Name'] ?? '', nameWidth,
                              bgColor: nameBgColor),
                          _fixedCell(
                              row['Number of Positive Matches'].toString(),
                              countWidth),
                          _fixedCell(
                              row['Number of Missing Required Alleles']
                                  .toString(),
                              countWidth),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // Scrollable Columns
        Expanded(
          child: Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: true,
            trackVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _sortedColumns.length * currentCellWidth,
                child: Column(
                  children: [
                    _buildScrollableHeader(),
                    Expanded(
                      child: ListView.builder(
                        controller: _verticalScrollController,
                        padding: EdgeInsets.only(bottom: 15.0),
                        itemCount: _epitopeResults.length,
                        itemExtent: currentCellHeight,
                        itemBuilder: (context, index) {
                          return _buildScrollableRow(_epitopeResults[index]);
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
    );
  }

  Widget _buildStickyHeader(double nameW, double countW) {
    return Container(
      height: currentHeaderHeight,
      color: Colors.grey[200],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _fixedCell('Epitope Name', nameW,
              isHeader: true, sortKey: 'Epitope Name'),
          _fixedCell('Pos', countW,
              isHeader: true,
              textColor: Colors.green,
              sortKey: 'Number of Positive Matches'),
          _fixedCell('Neg', countW,
              isHeader: true,
              textColor: Colors.red,
              sortKey: 'Number of Missing Required Alleles'),
        ],
      ),
    );
  }

  Widget _buildScrollableHeader() {
    return Container(
      height: currentHeaderHeight,
      color: Colors.grey[200],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _sortedColumns.map((allele) {
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
        }).toList(),
      ),
    );
  }

  Widget _buildScrollableRow(Map<String, dynamic> row) {
    final Set<String> positiveMatches =
        row['cached_positiveMatchesSet'] ?? <String>{};
    final Set<String> missingRequired =
        row['cached_missingRequiredSet'] ?? <String>{};

    return Container(
      height: currentCellHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: _sortedColumns.map((allele) {
          bool isPositive = positiveMatches.contains(allele);
          bool isMissing = missingRequired.contains(allele);

          Color cellColor = Colors.grey.shade100;
          if (isPositive) cellColor = Colors.green.shade600;
          if (isMissing) cellColor = Colors.red.shade600;

          String? label;
          if (isPositive || isMissing) {
            if (_recipientHlaSet.contains(allele)) {
              label = "S";
            } else if (_donorHlaSet.contains(allele)) {
              label = "D";
            }
          }

          return Container(
            width: currentCellWidth,
            height: currentCellHeight,
            decoration: BoxDecoration(
              color: cellColor,
              border: Border.all(color: Colors.white, width: 0.5),
            ),
            child: label != null
                ? Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: currentFontSize,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            offset: Offset(1, 1),
                            blurRadius: 2,
                            color: Colors.black45,
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          );
        }).toList(),
      ),
    );
  }

  Widget _fixedCell(
    String text,
    double width, {
    bool isHeader = false,
    Color? textColor,
    Color? bgColor,
    String? sortKey,
  }) {
    bool isSorted = sortKey != null && _sortColumn == sortKey;

    return InkWell(
      onTap: sortKey != null ? () => _sortResults(sortKey) : null,
      child: Container(
        width: width,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: bgColor ?? (isHeader ? Colors.grey[200] : Colors.white),
          border: Border(
            right: BorderSide(color: Colors.grey.shade300),
            bottom: isHeader
                ? BorderSide(color: Colors.grey.shade400, width: 2)
                : BorderSide.none,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                  color: textColor ?? Colors.black87,
                  fontSize: isHeader ? 12 : 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isHeader && sortKey != null)
              Icon(
                isSorted
                    ? (_sortAscending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward)
                    : Icons.sort,
                size: 12,
                color: isSorted ? Colors.blue : Colors.grey,
              ),
          ],
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
          Text(
            "Zoom: ${(_zoomLevel.value * 100).round()}%",
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
              value: _zoomLevel.value,
              min: 0.5,
              max: 3.0,
              divisions: 25,
              onChanged: (value) => setState(() => _zoomLevel.value = value),
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

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Row(
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
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0, right: 16.0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'v$_appVersion',
                style: TextStyle(fontSize: 10, color: Colors.grey[400]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
