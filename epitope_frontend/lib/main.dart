import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'allele_input.dart';
import 'graph_painter.dart';
import 'graph_header_painter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Epitope Finder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        useMaterial3: true,
      ),
      home: const EpitopeMatrixPage(),
    );
  }
}

class EpitopeMatrixPage extends StatefulWidget {
  const EpitopeMatrixPage({super.key});

  @override
  State<EpitopeMatrixPage> createState() => _EpitopeMatrixPageState();
}

class _EpitopeMatrixPageState extends State<EpitopeMatrixPage> {
  final String _appVersion = const String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );

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

  final String apiUrl = 'https://api.epitopefinder.dpdns.org';

  final ValueNotifier<double> _zoomLevel = ValueNotifier<double>(1.0);
  final double baseCellWidth = 28.0;
  final double baseCellHeight = 28.0;
  final double baseHeaderHeight = 140.0;

  double get currentCellWidth => baseCellWidth * _zoomLevel.value;
  double get currentCellHeight => baseCellHeight * _zoomLevel.value;
  double get currentHeaderHeight => baseHeaderHeight * _zoomLevel.value;
  double get currentFontSize => 12.0 * _zoomLevel.value;

  String? _sortColumn;
  bool _sortAscending = false; // Start initialized as descending

  void _updateZoom(double change) {
    _zoomLevel.value = (_zoomLevel.value + change).clamp(0.5, 3.0);
  }

  @override
  void initState() {
    super.initState();
    _antibodyFocusNode.addListener(_onAntibodyFocusChange);
    _fetchAlleles();

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
          'donor_hla': _selectedDonorHla.toList(),
        }),
      );

      if (response.statusCode == 200) {
        final List<dynamic> rawRows = jsonDecode(response.body);

        if (rawRows.isEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage = "No antibody matches found.";
          });
          return;
        }

        final Map<String, dynamic> firstRow =
            Map<String, dynamic>.from(rawRows.first as Map);
        final List<String> expandedAntibodies =
            (firstRow['expanded_input_alleles'] as List? ?? [])
                .map((e) => e.toString())
                .toList();

        List<String> positiveCols = List.from(expandedAntibodies)..sort();
        _userAllelesSet = expandedAntibodies.toSet();

        Set<String> negativeColSet = {};
        List<Map<String, dynamic>> processedRows = [];
        
        for (var rawRow in rawRows) {
          final Map<String, dynamic> row =
              Map<String, dynamic>.from(rawRow as Map);

          final List<String> positiveMatches =
              (row['Positive Matches'] as List? ?? [])
                  .map((e) => e.toString())
                  .toList();
          final List<String> missingRequired =
              (row['Missing Required Alleles'] as List? ?? [])
                  .map((e) => e.toString())
                  .toList();

          negativeColSet.addAll(missingRequired);

          bool hasS = row['cached_hasS'] == true;
          bool hasD = row['cached_hasD'] == true;
          bool isTheoretical = row['Theoretical'] == true;

          int posCount = row['Number of Positive Matches'] ?? 0;
          int negCount = row['Number of Missing Required Alleles'] ?? 0;

          // --- THE NEW MATH LOGIC (Pos - Neg) ---
          double matchRatio = posCount.toDouble() - negCount.toDouble();

          // Massive penalty for Self-Antibody to force it to the bottom
          if (hasS) {
            matchRatio -= 1000.0; 
          }

          processedRows.add({
            'Epitope Name': row['Epitope Name'],
            'cached_hasS': hasS,
            'cached_hasD': hasD,
            'isTheoretical': isTheoretical,
            'cached_highlightRow': hasS || hasD,
            'cached_positiveMatchesSet': positiveMatches.toSet(),
            'cached_missingRequiredSet': missingRequired.toSet(),
            'matchRatio': matchRatio,
            'Number of Positive Matches': posCount,
            'Number of Missing Required Alleles': negCount,
          });
        }

        // Apply Intelligent Sort on Initial Load
        processedRows.sort((a, b) {
          int ratioCmp = b['matchRatio'].compareTo(a['matchRatio']);
          if (ratioCmp != 0) return ratioCmp;
          
          // Tie-breaker
          int posA = a['Number of Positive Matches'] ?? 0;
          int posB = b['Number of Positive Matches'] ?? 0;
          return posB.compareTo(posA);
        });

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
        if (!_sortAscending) {
          // 2nd Click: It was descending, switch to ascending
          _sortAscending = true;
        } else {
          // 3rd Click: It was ascending, reset to intelligent sort
          _sortColumn = null;
        }
      } else {
        // 1st Click: Start with descending (big numbers on top)
        _sortColumn = column;
        _sortAscending = false;
      }

      if (_sortColumn == null) {
        // Reset to Intelligent Sort
        _epitopeResults.sort((a, b) {
          int ratioCmp = b['matchRatio'].compareTo(a['matchRatio']);
          if (ratioCmp != 0) return ratioCmp;
          
          int posA = a['Number of Positive Matches'] ?? 0;
          int posB = b['Number of Positive Matches'] ?? 0;
          return posB.compareTo(posA);
        });
      } else {
        // Apply Manual Column Sort
        _epitopeResults.sort((a, b) {
          dynamic valA = a[_sortColumn];
          dynamic valB = b[_sortColumn];
          int cmp;
          if (valA is num && valB is num) {
            cmp = valA.compareTo(valB);
          } else {
            cmp = valA.toString().compareTo(valB.toString());
          }
          // _sortAscending = false means Descending (-cmp handles large to small)
          return _sortAscending ? cmp : -cmp;
        });
      }
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
                  centerTitle: true, title: const Text('Epitope Finder')),
              body: Column(
                children: [
                  _buildSearchHeader(),
                  if (_epitopeResults.isNotEmpty) ...[
                    _buildLegend(),
                  ],
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _errorMessage.isNotEmpty
                            ? Center(
                                child: Text(
                                  _errorMessage,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              )
                            : _epitopeResults.isEmpty
                                ? const Center(
                                    child: Text(
                                        'Enter antibodies to view matrix.'),
                                  )
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
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12.0),
            child: Text(
              "Analysis Parameters",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
          ),
          Row(
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
                          style:
                              TextStyle(color: Colors.red[700], fontSize: 12),
                        ),
                      ),
                    AlleleInput(
                      label: 'Recipient Antibodies',
                      hintText: 'e.g. A*01:01, B*08:01, DP3',
                      selectedAlleles: _selectedAntibodies,
                      allAlleles: _allAlleles,
                      onChanged: () => setState(() {}),
                      isWarming: _isWarming,
                      focusNode: _antibodyFocusNode,
                    ),
                    const SizedBox(height: 12),
                    AlleleInput(
                      label: 'Recipient Typing',
                      hintText: 'e.g. A*02:01',
                      selectedAlleles: _selectedRecipientHla,
                      allAlleles: _allAlleles,
                      onChanged: () => setState(() {}),
                      fillColor: Colors.white,
                    ),
                    const SizedBox(height: 12),
                    AlleleInput(
                      label: 'Donor Typing',
                      hintText: 'e.g. B*44:02',
                      selectedAlleles: _selectedDonorHla,
                      allAlleles: _allAlleles,
                      onChanged: () => setState(() {}),
                      fillColor: Colors.white,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                height: 180,
                width: 140,
                child: ElevatedButton(
                  onPressed: fetchData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.analytics,
                        size: 32,
                        color: Colors.white,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Analyze',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: Colors.blueGrey.shade400),
                    const SizedBox(width: 8),
                    const Text(
                      "Matrix Legend",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.blueGrey),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    _legendItem(Colors.green.shade600, "Positive Match"),
                    _legendItem(Colors.red.shade600, "Missing Required"),
                    _legendItem(Colors.pink.shade100, "Self/DSA Highlight"),
                    _legendIcon("(T)", "Theoretical", Colors.blue.shade900),
                    _legendIcon("S", "Self HLA", Colors.blue.shade900),
                    _legendIcon("D", "DSA", Colors.orange.shade900),
                  ],
                ),
              ],
            ),
          ),
          _buildZoomControl(),
        ],
      ),
    );
  }

  Widget _legendIcon(String label, String description, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 6),
        Text(description,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }

  Widget _buildZoomControl() {
    return Container(
      padding: const EdgeInsets.only(left: 20),
      decoration: BoxDecoration(
        color: Colors.white, // Explicitly enforce pure white background
        border: Border(left: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            "Matrix Zoom: ${(_zoomLevel.value * 100).round()}%",
            style: TextStyle(
                color: Colors.grey[600],
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.zoom_out,
                    size: 18, color: Colors.blueGrey),
                onPressed: () => _updateZoom(-0.1),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              SizedBox(
                width: 140,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: _zoomLevel.value,
                    min: 0.5,
                    max: 3.0,
                    onChanged: (value) =>
                        setState(() => _zoomLevel.value = value),
                  ),
                ),
              ),
              IconButton(
                icon:
                    const Icon(Icons.zoom_in, size: 18, color: Colors.blueGrey),
                onPressed: () => _updateZoom(0.1),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMatrixContent() {
    const double nameWidth = 100;
    const double countWidth = 50;
    final double stickyTotalWidth = nameWidth + (countWidth * 2);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          SizedBox(
            width: stickyTotalWidth,
            child: Column(
              children: [
                _buildStickyHeader(nameWidth, countWidth),
                Expanded(
                  child: ListView.builder(
                    controller: _stickyVerticalScrollController,
                    padding: const EdgeInsets.only(bottom: 15.0),
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
                            _fixedCell(
                              row['Epitope Name'] ?? '',
                              nameWidth,
                              bgColor: nameBgColor,
                              isTheoretical: row['isTheoretical'] == true,
                            ),
                            _fixedCell(
                              row['Number of Positive Matches'].toString(),
                              countWidth,
                            ),
                            _fixedCell(
                              row['Number of Missing Required Alleles']
                                  .toString(),
                              countWidth,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
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
                          padding: const EdgeInsets.only(bottom: 15.0),
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
      ),
    );
  }

  Widget _buildStickyHeader(double nameW, double countW) {
    return Container(
      height: currentHeaderHeight,
      color: Colors.white,
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
      color: Colors.white,
      child: CustomPaint(
        size:
            Size(_sortedColumns.length * currentCellWidth, currentHeaderHeight),
        painter: GraphHeaderPainter(
          columns: _sortedColumns,
          userAllelesSet: _userAllelesSet,
          cellWidth: currentCellWidth,
          fontSize: currentFontSize,
          scrollController: _horizontalScrollController,
        ),
      ),
    );
  }

  Widget _buildScrollableRow(Map<String, dynamic> row) {
    final Set<String> positiveMatches =
        row['cached_positiveMatchesSet'] as Set<String>? ?? <String>{};
    final Set<String> missingRequired =
        row['cached_missingRequiredSet'] as Set<String>? ?? <String>{};

    return Container(
      height: currentCellHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: CustomPaint(
        size: Size(_sortedColumns.length * currentCellWidth, currentCellHeight),
        painter: GraphRowPainter(
          columns: _sortedColumns,
          positiveMatches: positiveMatches,
          missingRequired: missingRequired,
          cellWidth: currentCellWidth,
          recipientSet: _recipientHlaSet,
          donorSet: _donorHlaSet,
          fontSize: currentFontSize,
          scrollController: _horizontalScrollController,
          graphStartX: 0.0,
        ),
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
    bool isTheoretical = false,
  }) {
    bool isSorted = sortKey != null && _sortColumn == sortKey;

    return InkWell(
      onTap: sortKey != null ? () => _sortResults(sortKey) : null,
      child: Container(
        width: width,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: bgColor ?? Colors.white,
          border: Border(
            right: BorderSide(color: Colors.grey.shade300),
            bottom: isHeader
                ? BorderSide(color: Colors.grey.shade300, width: 2)
                : BorderSide.none,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: RichText(
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: TextStyle(
                    fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                    color: textColor ?? Colors.black87,
                    fontSize: isHeader ? 12 : 11,
                  ),
                  children: [
                    TextSpan(text: text),
                    if (isTheoretical)
                      TextSpan(
                        text: ' (T)',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: (isHeader ? 12 : 11) * 0.8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (isHeader && sortKey != null)
              Icon(
                isSorted
                    ? (!_sortAscending // Re-mapped UI Arrows to match user request
                        ? Icons.arrow_upward // Arrow Up: Big numbers on top (Descending)
                        : Icons.arrow_downward) // Arrow Down: Small numbers on top (Ascending)
                    : Icons.sort,
                size: 12,
                color: isSorted ? Colors.blue : Colors.grey,
              ),
          ],
        ),
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
              const Text('Created By: ',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey)),
              InkWell(
                onTap: () => launchUrl(Uri.parse(
                    "https://www.linkedin.com/in/rodin-hooshiyar-07036a3a0/")),
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
              const Text(' and ',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey)),
              InkWell(
                onTap: () => launchUrl(Uri.parse(
                    "https://www.linkedin.com/in/manxuan-michael-zhang-014b29237/")),
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