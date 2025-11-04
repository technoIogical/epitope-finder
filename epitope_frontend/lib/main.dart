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
      title: 'Allele Finder',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: AlleleFinderPage(),
    );
  }
}

class AlleleFinderPage extends StatefulWidget {
  @override
  _AlleleFinderPageState createState() => _AlleleFinderPageState();
}

class _AlleleFinderPageState extends State<AlleleFinderPage> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _patientController = TextEditingController();
  List<Map<String, dynamic>> data = [];
  bool isLoading = false;
  String errorMessage = '';

  // URL for the API
  final String apiUrl = 'https://epitope-server-998762220496.europe-west1.run.app';

  // Function to validate input format
  bool validateInput(String input) {
    // Check if the input is not empty and is comma-separated
    if (input.trim().isEmpty) {
      setState(() {
        errorMessage = 'Allele input cannot be empty.';
      });
      return false;
    }

    // Regex pattern for valid alleles like C*01:02, B*08:01
    RegExp regExp = RegExp(r'^[A-Za-z0-9]+\*[\d]+:[\d]+(,\s*[A-Za-z0-9]+\*[\d]+:[\d]+)*$');
    if (!regExp.hasMatch(input)) {
      setState(() {
        errorMessage = 'Invalid format. Please use comma-separated alleles (e.g., C*01:02, B*08:01).';
      });
      return false;
    }

    return true;
  }

  // Function to fetch data from the backend
  Future<void> fetchData(String inputAlleles, String patientAlleles) async {
    setState(() {
      isLoading = true;
      errorMessage = '';  // Reset any previous error messages
    });

    // Validate both allele inputs
    if (!validateInput(inputAlleles) || !validateInput(patientAlleles)) {
      setState(() {
        isLoading = false;  // Stop loading indicator if validation fails
      });
<<<<<<< Updated upstream
      return;
    }

    // Validate the input format (comma-separated alleles)
    RegExp regExp = RegExp(r'^[A-Za-z0-9]+\*[\d]+:[\d]+(,[A-Za-z0-9]+\*[\d]+:[\d]+)*$');
    if (!regExp.hasMatch(inputAlleles)) {
      setState(() {
        errorMessage = 'Invalid format. Please use comma-separated alleles (e.g., C*01:02, B*08:01).';
        isLoading = false;
      });
      return;
=======
      return;  // Exit if input validation fails
>>>>>>> Stashed changes
    }

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
<<<<<<< Updated upstream
        body: jsonEncode({'input_alleles': inputAlleles.split(',')}),  // Split input alleles by comma
=======
        body: jsonEncode({
          'input_alleles': inputAlleles.split(',').map((allele) => allele.trim()).toList(),
          'patient_alleles': patientAlleles.split(',').map((allele) => allele.trim()).toList(),
        }),
>>>>>>> Stashed changes
      );

      if (response.statusCode == 200) {
        final List<dynamic> rows = jsonDecode(response.body);
        setState(() {
          data = rows.map((e) => e as Map<String, dynamic>).toList();
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load data. Status Code: ${response.statusCode}.';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'An error occurred: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Allele Finder')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Allele Input for Testing Positivity
            Text('Enter Alleles to Test for Positivity:', style: TextStyle(fontSize: 18)),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'e.g., C*01:02, B*08:01',
                border: OutlineInputBorder(),
                errorText: errorMessage.isNotEmpty ? errorMessage : null, // Display error message
              ),
            ),
            SizedBox(height: 16),

            // Patient Allele Input
            Text('Enter Patient Alleles:', style: TextStyle(fontSize: 18)),
            TextField(
              controller: _patientController,
              decoration: InputDecoration(
                hintText: 'e.g., C*01:02, C*01:03',
                border: OutlineInputBorder(),
                errorText: errorMessage.isNotEmpty ? errorMessage : null, // Display error message
              ),
            ),
            SizedBox(height: 20),

            ElevatedButton(
              onPressed: () {
                fetchData(_controller.text, _patientController.text); // Send both inputs to the API
              },
              child: Text('Submit'),
            ),

            // Show Loading Indicator or Error Message
            isLoading
                ? Center(child: CircularProgressIndicator())
                : errorMessage.isNotEmpty
                    ? Center(child: Text(errorMessage, style: TextStyle(color: Colors.red)))
                    : Expanded(
                        child: data.isEmpty
                            ? Center(child: Text('No matches found'))
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: [
                                    DataColumn(label: Text('Epitope')),
                                    // Dynamically generate columns for each allele from the response data
                                    ...data[0]['Alleles']?.map((allele) => DataColumn(label: Text(allele))) ?? [],
                                    DataColumn(label: Text('Total Positive Alleles')),
                                    DataColumn(label: Text('Negative Alleles')),
                                  ],
                                  rows: data.map((result) {
                                    // Ensure the correct number of cells for each row
                                    int totalPositive = result['Positive Matches']?.length ?? 0;
                                    int negativeAlleles = result['Missing Required Alleles']?.length ?? 0;

                                    // Create row cells for alleles and additional data
                                    List<DataCell> rowCells = [
                                      DataCell(Text(result['Epitope Name'] ?? '')),
                                      // Add cells for each allele (color-coded)
                                      ...(result['Positive Matches']?.map((match) {
                                        return DataCell(
                                          Container(
                                            color: match == 'positive' ? Colors.green : Colors.red,
                                            height: 30,
                                            width: 30,
                                          ),
                                        );
                                      })?.toList() ?? []),
                                      DataCell(Text('$totalPositive')), // Total Positive Alleles
                                      DataCell(Text('$negativeAlleles')), // Negative Alleles
                                    ];

                                    // Ensure each row has the same number of cells as the columns
                                    while (rowCells.length < 6) {
                                      rowCells.add(DataCell(Text('')));  // Add empty cells if necessary
                                    }

                                    return DataRow(
                                      cells: rowCells,
                                    );
                                  }).toList(),
                                ),
                              ),
                      ),
          ],
        ),
      ),
    );
  }
}
