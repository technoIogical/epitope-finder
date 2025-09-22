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

  // Fetch epitope data from backend
  Future<void> fetchData(String inputAlleles) async {
    setState(() {
      isLoading = true;
      errorMessage = '';  // Reset error message
    });

    try {
      final response = await http.post(
        Uri.parse('https://<YOUR-BACKEND-ENDPOINT>/get-epitopes'),  // Replace with your backend URL
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'input_alleles': inputAlleles.split(',')}),  // Split input alleles by comma
      );

      if (response.statusCode == 200) {
        final List<dynamic> rows = jsonDecode(response.body);
        setState(() {
          data = rows.map((e) => e as Map<String, dynamic>).toList();
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load data. Please try again later.';
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
            Text('Enter Alleles:', style: TextStyle(fontSize: 18)),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Enter allele sequence (e.g., C*01:02, B*08:01)',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (input) {
                // Fetch data from backend
                fetchData(input);
              },
            ),
            SizedBox(height: 20),
            isLoading
                ? Center(child: CircularProgressIndicator()) // Show loading indicator while fetching data
                : errorMessage.isNotEmpty
                    ? Center(child: Text(errorMessage, style: TextStyle(color: Colors.red)))  // Show error message
                    : Expanded(
                        child: ListView.builder(
                          itemCount: data.length,
                          itemBuilder: (context, index) {
                            var result = data[index];
                            return Card(
                              child: ListTile(
                                title: Text('Epitope: ${result['Epitope Name']}'),
                                subtitle: Text(
                                    'Locus: ${result['Locus']}\nPositive Matches: ${result['Positive Matches'].join(', ')}\nMissing Alleles: ${result['Missing Required Alleles'].join(', ')}'),
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
