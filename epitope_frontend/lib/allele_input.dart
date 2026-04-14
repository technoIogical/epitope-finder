import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Added to allow cross-referencing for highlighting
  final List<String>? recipientAlleles;
  final List<String>? donorAlleles;

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
    this.recipientAlleles,
    this.donorAlleles,
  });

  @override
  State<AlleleInput> createState() => _AlleleInputState();
}

class _AlleleInputState extends State<AlleleInput> {
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _internalFocusNode;
  bool _isFocused = false;
  DateTime? _backspaceStartTime;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = widget.focusNode ?? FocusNode();
    _internalFocusNode.addListener(_handleFocusChange);

    _controller.addListener(() {
      if (mounted) setState(() {});
    });

    _internalFocusNode.onKeyEvent = (FocusNode node, KeyEvent event) {
      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        if (_controller.text.isEmpty && widget.selectedAlleles.isNotEmpty) {
          if (event is KeyDownEvent || event is KeyRepeatEvent) {
            _backspaceStartTime ??= DateTime.now();
            final holdDuration =
                DateTime.now().difference(_backspaceStartTime!);

            setState(() {
              int deleteCount = 1;
              if (holdDuration.inSeconds >= 5) {
                deleteCount = widget.selectedAlleles.length;
              } else if (holdDuration.inSeconds >= 3) {
                deleteCount = 5;
              }
              for (int i = 0; i < deleteCount; i++) {
                if (widget.selectedAlleles.isNotEmpty) {
                  widget.selectedAlleles.removeLast();
                }
              }
            });

            widget.onChanged();
            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            _backspaceStartTime = null;
          }
        } else {
          _backspaceStartTime = null;
        }
      } else if (event is KeyUpEvent) {
        _backspaceStartTime = null;
      }
      return KeyEventResult.ignored;
    };
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _internalFocusNode.hasFocus;
      });
    }
  }

  BoxDecoration _getDropdownItemDecoration(String allele) {
    final upper = allele.toUpperCase();
    Color bgColor = Colors.white;

    if (upper.startsWith('A*') || upper.startsWith('A-')) {
      bgColor = const Color(0xFFFEE4CB);
    } else if (upper.startsWith('B*') || upper.startsWith('B-')) {
      bgColor = const Color(0xFFEAE4F2);
    } else if (upper.startsWith('C*') || upper.startsWith('C-')) {
      bgColor = const Color(0xFFD6EAF8);
    } else if (upper.startsWith('DRB1')) {
      bgColor = const Color(0xFFC0E8E4);
    } else if (upper.startsWith('DR')) {
      bgColor = const Color(0xFFDDF2F0);
    } else if (upper.startsWith('DQB1')) {
      bgColor = const Color(0xFFEAAFAF);
    } else if (upper.startsWith('DQA1') || upper.startsWith('DQ')) {
      bgColor = const Color(0xFFF5D6D6);
    } else if (upper.startsWith('DPB1')) {
      bgColor = const Color(0xFFBCBBE0);
    } else if (upper.startsWith('DPA1') || upper.startsWith('DP')) {
      bgColor = const Color(0xFFDEDDF0);
    }

    return BoxDecoration(color: bgColor);
  }

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

  // Normalizer for EXACT dropdown matches
  String _normalize(String s) {
    return s
        .replaceAll('-', '')
        .toUpperCase()
        .replaceAllMapped(RegExp(r'^([A-Z]+)0+'), (m) => m.group(1)!);
  }

  // NEW: Highly robust HLA parser for dynamic Serotype-to-Allele highlighting
  bool _isRelated(String a, String b) {
    String simplify(String s) {
      // 1. Remove all non-alphanumeric characters (strips *, :, -)
      String clean = s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      
      // 2. Remove 'W' (used in historical serotypes like Cw1, DPw3)
      clean = clean.replaceAll('W', '');
      
      // 3. Flatten complex loci to base locus for serotype matching (e.g., DRB1 -> DR)
      clean = clean.replaceFirst(RegExp(r'^DRB[1345]'), 'DR')
                   .replaceFirst(RegExp(r'^DQ[AB]1'), 'DQ')
                   .replaceFirst(RegExp(r'^DP[AB]1'), 'DP');
                   
      // 4. Remove leading zeros directly after the locus letters (e.g. A0101 -> A101)
      clean = clean.replaceAllMapped(RegExp(r'^([A-Z]+)0+'), (m) => m.group(1)!);
      
      return clean;
    }

    String normA = simplify(a);
    String normB = simplify(b);

    // If typing is "A1" (norm: A1) and Antibody is "A*01:01" (norm: A101), this will match.
    return normA.startsWith(normB) || normB.startsWith(normA);
  }

  void _processMultiInput(String input, TextEditingController controller) {
    final rawEntries = input.split(RegExp(r'[,\s\n\t]+'));
    final validAlleles = rawEntries
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty && entry != '-')
        .toList();

    if (validAlleles.isEmpty) {
      if (input.isNotEmpty) controller.clear();
      return;
    }

    bool changed = false;
    List<String> invalidEntries = [];

    setState(() {
      for (String entry in validAlleles) {
        final String normalizedEntry = _normalize(entry);

        String? match;
        try {
          match = widget.allAlleles.firstWhere(
            (a) => _normalize(a) == normalizedEntry,
          );
        } catch (_) {
          match = null;
        }

        if (match != null) {
          if (!widget.selectedAlleles.contains(match)) {
            widget.selectedAlleles.add(match);
            changed = true;
          }
        } else {
          invalidEntries.add(entry);
        }
      }
    });

    if (invalidEntries.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unknown items: ${invalidEntries.join(', ')}. These were not added.',
          ),
          backgroundColor: Colors.orange[800],
        ),
      );
    }

    if (changed) {
      widget.onChanged();
    }

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
              final String normalizedQuery = _normalize(query);

              final List<String> fuzzyMatches =
                  widget.allAlleles.where((option) {
                final String normalizedOption =
                    _normalize(option.toLowerCase());
                return normalizedOption.contains(normalizedQuery) ||
                    option.toLowerCase().contains(query);
              }).toList();

              fuzzyMatches.sort((a, b) {
                final aLower = a.toLowerCase();
                final bLower = b.toLowerCase();
                final aNorm = _normalize(aLower);
                final bNorm = _normalize(bLower);

                if (aLower.startsWith(query) && !bLower.startsWith(query)) return -1;
                if (!aLower.startsWith(query) && bLower.startsWith(query)) return 1;

                if (aNorm.startsWith(normalizedQuery) &&
                    !bNorm.startsWith(normalizedQuery)) return -1;
                if (!aNorm.startsWith(normalizedQuery) &&
                    bNorm.startsWith(normalizedQuery)) return 1;

                return aLower.compareTo(bLower);
              });

              return fuzzyMatches.take(50);
            },
            onSelected: (String selection) {
              if (!widget.selectedAlleles.contains(selection)) {
                setState(() {
                  widget.selectedAlleles.add(selection);
                  widget.onChanged();
                });
              }
              _controller.clear();
              _internalFocusNode.requestFocus();
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => focusNode.requestFocus(),
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
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.isWarming)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                        (allele) {
                          // Evaluates matches using the robust parser
                          final bool isSerotype = !allele.contains('*');
                          final bool isSelfMatch = widget.recipientAlleles
                                  ?.any((r) => _isRelated(r, allele)) ?? false;
                          final bool isDsa = widget.donorAlleles
                                  ?.any((d) => _isRelated(d, allele)) ?? false;

                          Color chipBgColor;
                          Color chipBorderColor;
                          Color textColor;
                          Color iconColor;

                          if (isSelfMatch) {
                            chipBgColor = Colors.blue.shade800; // Dark Blue
                            chipBorderColor = Colors.blue.shade900;
                            textColor = Colors.white;
                            iconColor = Colors.white70;
                          } else if (isDsa) {
                            chipBgColor = Colors.orange.shade600; // Orange
                            chipBorderColor = Colors.orange.shade800;
                            textColor = Colors.white;
                            iconColor = Colors.white70;
                          } else if (isSerotype) {
                            chipBgColor = Colors.blue[100]!; // Light blue
                            chipBorderColor = Colors.blue.shade300;
                            textColor = Colors.black87;
                            iconColor = Colors.blue[900]!;
                          } else {
                            chipBgColor = Colors.grey[200]!; // Default grey
                            chipBorderColor = Colors.grey.shade400;
                            textColor = Colors.black87;
                            iconColor = Colors.grey;
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: chipBgColor,
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(color: chipBorderColor),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  allele,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSerotype || isSelfMatch || isDsa
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      widget.selectedAlleles.remove(allele);
                                      widget.onChanged();
                                    });
                                  },
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: iconColor,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      SizedBox(
                        width: 150,
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: (val) {
                            if (val.contains(',') ||
                                val.contains('\n') ||
                                val.contains('\t')) {
                              _processMultiInput(val, controller);
                            }
                          },
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                          onSubmitted: (value) {
                            if (value.contains(',') ||
                                value.contains(' ') ||
                                value.contains('-')) {
                              _processMultiInput(value, controller);
                            } else if (value.isNotEmpty &&
                                widget.allAlleles.contains(value)) {
                              onFieldSubmitted();
                            } else {
                              _processMultiInput(value, controller);
                            }
                            focusNode.requestFocus();
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
                  surfaceTintColor: Colors.transparent,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: 250,
                      maxWidth: outerConstraints.maxWidth,
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (BuildContext context, int index) {
                        final String option = options.elementAt(index);
                        return Container(
                          decoration:
                              _getDropdownItemDecoration(option).copyWith(
                            border: const Border(
                                bottom: BorderSide(
                                    color: Colors.white, width: 1.5)),
                          ),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              option,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                              softWrap: false,
                              overflow: TextOverflow.visible,
                            ),
                            onTap: () => onSelected(option),
                          ),
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