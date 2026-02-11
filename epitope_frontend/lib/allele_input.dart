import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, outerConstraints) {
      return MouseRegion(
        cursor: SystemMouseCursors.text,
        child: RawAutocomplete<String>(
          textEditingController: _controller,
          focusNode: _internalFocusNode,
          optionsBuilder: (TextEditingValue textEditingValue) async {
            if (textEditingValue.text.isEmpty) {
              return const Iterable<String>.empty();
            }

            final String query = textEditingValue.text.toLowerCase();

            // Use compute for filtering if the list is large to avoid jank
            if (widget.allAlleles.length > 500) {
              return await compute(_filterAlleles, {
                'query': query,
                'alleles': widget.allAlleles,
              });
            } else {
              return _filterAlleles({
                'query': query,
                'alleles': widget.allAlleles,
              });
            }
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
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  suffixIcon: widget.isWarming
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ...widget.selectedAlleles.map((allele) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(allele,
                                  style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    widget.selectedAlleles.remove(allele);
                                    widget.onChanged();
                                  });
                                },
                                child: const Icon(Icons.close,
                                    size: 14, color: Colors.grey),
                              ),
                            ],
                          ),
                        )),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: (val) {
                          // Only rebuild the input decorator local state
                          if (mounted) {
                            setState(() {});
                          }
                        },
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onSubmitted: (value) {
                          if (value.isNotEmpty &&
                              widget.allAlleles.contains(value)) {
                            onFieldSubmitted();
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
    });
  }
}

/// Independent filtering function that can be run in a separate isolate
List<String> _filterAlleles(Map<String, dynamic> params) {
  final String query = params['query'];
  final List<String> alleles = params['alleles'] as List<String>;

  final List<String> startsWith = [];
  final List<String> contains = [];

  for (final option in alleles) {
    final lowerOption = option.toLowerCase();
    if (lowerOption.startsWith(query)) {
      startsWith.add(option);
    } else if (lowerOption.contains(query)) {
      contains.add(option);
    }
    // Limit results early to save time and avoid heavy UI rendering
    if (startsWith.length + contains.length >= 50) break;
  }

  return [...startsWith, ...contains].take(50).toList();
}
