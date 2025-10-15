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
  List<Map<String, dynamic>> data = [];
  bool isLoading = false;
  String errorMessage = '';
  
  // URL for the API (make it dynamic if needed for environments)
  final String apiUrl = 'https://epitope-server-998762220496.europe-west1.run.app';

  // Function to fetch data from the backend
  Future<void> fetchData(String inputAlleles) async {
    setState(() {
      isLoading = true;
      errorMessage = '';  // Reset any previous error messages
    });

    if (inputAlleles.isEmpty) {
      setState(() {
        errorMessage = 'Please enter allele sequence.';
        isLoading = false;
      });
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
    }

    try {
      // Send POST request to your backend API
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'input_alleles': inputAlleles.split(',')}),  // Split input alleles by comma
      );

      if (response.statusCode == 200) {
        // If the response is successful, parse the JSON data
        final List<dynamic> rows = jsonDecode(response.body);
        setState(() {
          data = rows.map((e) => e as Map<String, dynamic>).toList();
        });
      } else {
        // If the response is not successful, show an error message
        setState(() {
          errorMessage = 'Failed to load data. Status Code: ${response.statusCode}. Please try again later.';
        });
      }
    } catch (e) {
      // If there's any error during the request
      setState(() {
        errorMessage = 'An error occurred: $e';
      });
    } finally {
      setState(() {
        isLoading = false;  // Stop loading indicator
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
            Text('Enter Alleles:', style: TextStyle(fontSize: 18)),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Enter allele sequence (e.g., C*01:02, B*08:01)',
                border: OutlineInputBorder(),
                errorText: errorMessage.isEmpty ? null : errorMessage, // Display error message if any
              ),
              onSubmitted: (input) {
                // When the user submits the input, call fetchData
                fetchData(input);
              },
            ),
            SizedBox(height: 20),
            isLoading
                ? Center(child: CircularProgressIndicator())  // Show loading indicator
                : errorMessage.isNotEmpty
                    ? Center(child: Text(errorMessage, style: TextStyle(color: Colors.red)))  // Show error message
                    : Expanded(
                        child: data.isEmpty
                            ? Center(child: Text('No matches found'))  // Show when no data found
                            : ListView.builder(
                                itemCount: data.length,
                                itemBuilder: (context, index) {
                                  var result = data[index];
                                  return Card(
                                    margin: EdgeInsets.symmetric(vertical: 8.0),
                                    child: ListTile(
                                      title: Text('Epitope: ${result['Epitope Name']}'),
                                      subtitle: Text(
                                          'Locus: ${result['Locus']}\n'
                                          'Positive Matches: ${result['Positive Matches'].join(', ')}\n'
                                          'Missing Alleles: ${result['Missing Required Alleles'].join(', ')}',
                                          style: TextStyle(fontSize: 14)),
                                    ),
                                  );
                                },
                              ),
                      ),
          ],
        ),
      ),
    );
  }
}
