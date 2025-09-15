import 'package:flutter/material.dart';

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

class AlleleFinderPage extends StatelessWidget {
  final List<Map<String, String>> data = [
    {
      'Epitope': '9Y',
      'Positive Matches': 'C*01:02, B*08:01',
      'Missing Alleles': 'A*01:01',
    },
    {
      'Epitope': '16H',
      'Positive Matches': 'A*01:01',
      'Missing Alleles': 'B*08:01',
    },
  ];

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
              decoration: InputDecoration(
                hintText: 'Enter allele sequence here',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (input) {
                // Process input alleles (you can integrate backend later)
                print("User input: $input");
              },
            ),
            SizedBox(height: 20),
            Text('Results:', style: TextStyle(fontSize: 18)),
            Expanded(
              child: ListView.builder(
                itemCount: data.length,
                itemBuilder: (context, index) {
                  var result = data[index];
                  return Card(
                    child: ListTile(
                      title: Text('Epitope: ${result['Epitope']}'),
                      subtitle: Text('Positive Matches: ${result['Positive Matches']}\nMissing Alleles: ${result['Missing Alleles']}'),
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
