import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';

class AlleleInput extends StatefulWidget {
  final String label;
  final String hintText;
  final List<String> selectedAlleles;
  final List<String> allAlleles;
  final VoidCallback onChanged;
  final Color? fillColor;
  final bool isWarming;
  final FocusNode? focusNode;

  const AlleleInput({
    super.key,
    required this.label,
    required this.hintText,
    required this.selectedAlleles,
    required this.allAlleles,
    required this.onChanged,
    this.fillColor,
    this.isWarming = false,
    this.focusNode,
  });

  @override
  State<AlleleInput> createState() => _AlleleInputState();
}

class _AlleleInputState extends State<AlleleInput> {
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _internalFocusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = widget.focusNode ?? FocusNode();
    _internalFocusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _internalFocusNode.hasFocus;
      });
    }
  }

  // ── File Upload Logic ──────────────────
  Future<void> _pickAndParseFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;

      final content = utf8.decode(bytes);
      List<String> items = [];

      if (file.extension == 'json') {
        final dynamic data = jsonDecode(content);
        if (data is List) {
          items = data.map((e) => e.toString()).toList();
        } else if (data is Map) {
          data.forEach((key, value) {
            if (value is List) {
              items.addAll(value.map((e) => e.toString()));
            }
          });
        }
      } else if (file.extension == 'csv') {
        final List<List<dynamic>> csvTable =
            const CsvToListConverter().convert(content);
        for (final row in csvTable) {
          for (final cell in row) {
            if (cell != null && cell.toString().isNotEmpty) {
              items.add(cell.toString().trim());
            }
          }
        }
      }

      bool changed = false;
      for (String item in items) {
        final String trimmed = item.trim();
        if (trimmed.isEmpty) continue;

        final String match = widget.allAlleles.firstWhere(
          (a) => a.toLowerCase() == trimmed.toLowerCase(),
          orElse: () => '',
        );

        if (match.isNotEmpty && !widget.selectedAlleles.contains(match)) {
          widget.selectedAlleles.add(match);
          changed = true;
        }
      }

      if (changed) {
        widget.onChanged();
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error picking or parsing file: $e');
      }
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _internalFocusNode.dispose();
    } else {
      _internalFocusNode.removeListener(_handleFocusChange);
    }
    _controller.dispose();
    super.dispose();
  }

  // --- NEW PARSING LOGIC ---
  void _processMultiInput(String input, TextEditingController controller) {
    // Split by commas, spaces, newlines, or tabs
    final rawEntries = input.split(RegExp(r'[,\s\n\t]+'));
    
    // Filter out empty spaces and explicit dashes
    final validAlleles = rawEntries
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty && entry != '-')
        .toList();

    if (validAlleles.isEmpty) {
      if (input.isNotEmpty) controller.clear();
      return;
    }

    bool changed = false;
    setState(() {
      for (String allele in validAlleles) {
        if (!widget.selectedAlleles.contains(allele)) {
          widget.selectedAlleles.add(allele);
          changed = true;
        }
      }
    });

    if (changed) {
      widget.onChanged();
    }
    
    // Clear the text field after successful processing
    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, outerConstraints) {
        return MouseRegion(
          cursor: SystemMouseCursors.text,
          child: RawAutocomplete<String>(
            textEditingController: _controller,
            focusNode: _internalFocusNode,
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return const Iterable<String>.empty();
              }
              final String query = textEditingValue.text.toLowerCase();
              final List<String> startsWith = widget.allAlleles
                  .where(
                    (String option) => option.toLowerCase().startsWith(query),
                  )
                  .toList();
              final List<String> contains = widget.allAlleles
                  .where(
                    (String option) =>
                        option.toLowerCase().contains(query) &&
                        !option.toLowerCase().startsWith(query),
                  )
                  .toList();
              return [...startsWith, ...contains].take(50);
            },
            onSelected: (String selection) {
              setState(() {
                if (!widget.selectedAlleles.contains(selection)) {
                  widget.selectedAlleles.add(selection);
                  widget.onChanged();
                }
                _controller.clear();
              });
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  focusNode.requestFocus();
                },
                child: InputDecorator(
                  isFocused: _isFocused,
                  isEmpty:
                      widget.selectedAlleles.isEmpty && controller.text.isEmpty,
                  decoration: InputDecoration(
                    labelText: widget.label,
                    hintText: widget.hintText,
                    fillColor: widget.fillColor ?? Colors.white,
                    filled: true,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.isWarming)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.upload_file, size: 20),
                          tooltip: 'Upload CSV or JSON',
                          onPressed: _pickAndParseFile,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...widget.selectedAlleles.map(
                        (allele) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                allele,
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    widget.selectedAlleles.remove(allele);
                                    widget.onChanged();
                                  });
                                },
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )),
                      // The corrected, single SizedBox and TextField
                      SizedBox(
                        width: 150,
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: (val) {
                            setState(() {});
                            // Instantly catch pasted tabular data (commas, tabs, newlines)
                            if (val.contains(',') || val.contains('\n') || val.contains('\t')) {
                              _processMultiInput(val, controller);
                            }
                          },
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                          onSubmitted: (value) {
                            // Catch entries submitted via Enter key with spaces or dashes
                            if (value.contains(',') || value.contains(' ') || value.contains('-')) {
                              _processMultiInput(value, controller);
                            } else if (value.isNotEmpty &&
                                widget.allAlleles.contains(value)) {
                              onFieldSubmitted(); // Standard autocomplete behavior
                            } else {
                              // Catch-all for a single allele manually typed without Autocomplete
                              _processMultiInput(value, controller);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4.0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: 200,
                      maxWidth: outerConstraints.maxWidth,
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (BuildContext context, int index) {
                        final String option = options.elementAt(index);
                        return ListTile(
                          dense: true,
                          title: Text(
                            option,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                          ),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}