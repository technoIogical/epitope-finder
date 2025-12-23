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
  List<Map<String, dynamic>> _epitopeResults = [];
  Set<String> _dynamicAlleleColumns = {}; // Stores all unique alleles to display as columns
  bool _isLoading = false;
  String _errorMessage = '';

  // Ensure this matches your deployed Cloud Function URL
  final String apiUrl = 'https://epitope-server-998762220496.europe-west1.run.app';

  Future<void> fetchData(String inputAlleles) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _epitopeResults = [];
      _dynamicAlleleColumns = {};
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
        final List<dynamic> rows = jsonDecode(response.body);
        
        // 1. Process Data
        List<Map<String, dynamic>> processedRows = rows.map((e) => e as Map<String, dynamic>).toList();

        // 2. Build the Column List (Matrix Header)
        // We want columns for: All User Inputs + Any "Missing Required" alleles found in the results
        Set<String> columnSet = Set.from(parsedInput);
        
        for (var row in processedRows) {
          final missing = List<String>.from(row['Missing Required Alleles'] ?? []);
          columnSet.addAll(missing);
        }

        // Sort columns alphabetically for cleaner reading
        List<String> sortedColumns = columnSet.toList()..sort();

        setState(() {
          _epitopeResults = processedRows;
          _dynamicAlleleColumns = sortedColumns.toSet();
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
    return Scaffold(
      appBar: AppBar(
        title: Text('HLA Epitope Registry'),
        elevation: 2,
      ),
      body: Column(
        children: [
          // --- Search Section ---
          Container(
            padding: EdgeInsets.all(16.0),
            color: Colors.grey[100],
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      labelText: 'Patient Alleles (Input)',
                      hintText: 'e.g., A*01:01, B*08:01, DRB1*15:01',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
                SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () => fetchData(_controller.text),
                  icon: Icon(Icons.search),
                  label: Text('Analyze Matches'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
              ],
            ),
          ),
          
          // --- Legend Section ---
          if (_epitopeResults.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  _buildLegendItem(Colors.green.shade400, "Positive Match"),
                  SizedBox(width: 16),
                  _buildLegendItem(Colors.red.shade400, "Missing Required (Negative)"),
                  SizedBox(width: 16),
                  _buildLegendItem(Colors.grey.shade300, "Not Relevant"),
                ],
              ),
            ),

          Divider(height: 1),

          // --- Matrix Result Section ---
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(child: Text(_errorMessage, style: TextStyle(color: Colors.red)))
                    : _epitopeResults.isEmpty
                        ? Center(child: Text('Enter alleles to view the Epitope Matrix.'))
                        : _buildMatrixTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      children: [
        Container(width: 16, height: 16, color: color),
        SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildMatrixTable() {
    // Convert Set to List for indexed access
    final List<String> columnList = _dynamicAlleleColumns.toList();

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(Colors.grey[200]),
          columnSpacing: 20,
          border: TableBorder.all(color: Colors.grey.shade300),
          
          columns: [
            DataColumn(label: Text('Epitope', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Pos (+)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
            DataColumn(label: Text('Neg (-)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
            // Dynamic Columns for Alleles
            ...columnList.map((allele) => DataColumn(
                  label: RotatedBox(
                    quarterTurns: 0, // You can change to 3 if columns get too wide
                    child: Text(allele, style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                )),
          ],
          
          rows: _epitopeResults.map((row) {
            final positiveMatches = Set<String>.from(row['Positive Matches'] ?? []);
            final missingRequired = Set<String>.from(row['Missing Required Alleles'] ?? []);

            return DataRow(cells: [
              // Fixed Info Columns
              DataCell(Text(row['Epitope Name'] ?? 'Unknown', style: TextStyle(fontWeight: FontWeight.bold))),
              DataCell(Text(row['Number of Positive Matches'].toString())),
              DataCell(Text(row['Number of Missing Required Alleles'].toString())),
              
              // Dynamic Allele Matrix Cells
              ...columnList.map((allele) {
                Color? cellColor;
                
                if (positiveMatches.contains(allele)) {
                  cellColor = Colors.green.shade400;
                } else if (missingRequired.contains(allele)) {
                  cellColor = Colors.red.shade400;
                } else {
                  cellColor = Colors.grey.shade100;
                }

                return DataCell(
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: cellColor,
                  ),
                );
              }),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}