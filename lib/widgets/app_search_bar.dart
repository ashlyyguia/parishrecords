import 'package:flutter/material.dart';

import '../app/app_colors.dart';

/// Uniform search field used across all list/filter pages.
///
/// Handles its own clear button (shown while there is text) so callers only
/// provide a [controller], a [hintText], and an [onChanged] callback. Optional
/// [trailing] widgets (e.g. a refresh button) sit to the right of the field.
///
/// ```dart
/// AppSearchBar(
///   controller: _searchCtrl,
///   hintText: 'Search households…',
///   onChanged: (_) => setState(() {}),
/// )
/// ```
class AppSearchBar extends StatefulWidget {
  const AppSearchBar({
    super.key,
    required this.controller,
    this.hintText = 'Search…',
    this.onChanged,
    this.onClear,
    this.autofocus = false,
    this.focusNode,
    this.trailing = const <Widget>[],
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  /// Called after the field is cleared via the clear button.
  final VoidCallback? onClear;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Optional buttons rendered to the right of the field.
  final List<Widget> trailing;

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    // Rebuild so the clear button appears/disappears with the text.
    if (mounted) setState(() {});
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hintText,
        hintStyle: const TextStyle(color: AppColors.slate400),
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.slate500),
        suffixIcon: widget.controller.text.isNotEmpty
            ? IconButton(
                onPressed: _clear,
                tooltip: 'Clear',
                icon: const Icon(Icons.close_rounded, size: 20),
                color: AppColors.slate500,
              )
            : null,
        filled: true,
        fillColor: AppColors.field,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );

    if (widget.trailing.isEmpty) return field;

    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        ...widget.trailing,
      ],
    );
  }
}

/// Uniform filter chip that pairs with [AppSearchBar].
///
/// Selected chips fill with the brand color; unselected chips use a soft
/// tinted surface with a hairline border. Optional leading [icon].
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.slate600;
    return Material(
      color: selected ? AppColors.primary : AppColors.tint,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.tintStrong,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
