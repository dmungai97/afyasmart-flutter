import 'package:flutter/material.dart';

/// Shared pieces of the sign-in screens. The teal backdrop and ringed logo
/// that used to live here were removed when login and register moved to the
/// paper-and-ink look of the welcome screen; [AuthField] is also used by the
/// profile screens.
abstract final class AuthPalette {
  static const teal = Color(0xFF005454);
  static const fieldIcon = Color(0xFF5F6B7A);

  /// 4.6:1 on the field fill. The previous #9AA7A7 was 2.4:1, too faint to
  /// read placeholder text on a phone outdoors.
  static const hint = Color(0xFF6B7676);
}

/// A labelled text field with a leading icon and a teal focus ring —
/// the inputWrap / inputWrapFocused pair from the RN screens.
class AuthField extends StatefulWidget {
  const AuthField({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.keyboardType,
    this.obscure = false,
    this.showCheckWhenFilled = false,
    this.textInputAction,
    this.onSubmitted,
    this.enabled = true,
    this.helperText,
    this.autofillHints,
    super.key,
  });

  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscure;
  final bool showCheckWhenFilled;
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmitted;
  final bool enabled;
  final String? helperText;

  /// Lets password managers and the browser fill saved credentials, e.g.
  /// [AutofillHints.email] and [AutofillHints.password].
  final Iterable<String>? autofillHints;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  final _focus = FocusNode();
  late bool _obscured = widget.obscure;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    widget.controller.addListener(_onText);
  }

  void _onText() {
    if (widget.showCheckWhenFilled) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2D3748),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          enabled: widget.enabled,
          autofillHints: widget.autofillHints,
          keyboardType: widget.keyboardType,
          obscureText: _obscured,
          autocorrect: false,
          textInputAction: widget.textInputAction,
          onSubmitted: (_) => widget.onSubmitted?.call(),
          cursorColor: AuthPalette.teal,
          style: TextStyle(
            fontSize: 15,
            color: widget.enabled ? const Color(0xFF1A202C) : AuthPalette.hint,
          ),
          decoration: InputDecoration(
            hintText: widget.hint,
            helperText: widget.helperText,
            hintStyle: const TextStyle(color: AuthPalette.hint),
            filled: true,
            fillColor: const Color(0xFFF7FAFA),
            prefixIcon: Icon(
              widget.icon,
              size: 20,
              color: focused ? AuthPalette.teal : AuthPalette.fieldIcon,
            ),
            suffixIcon: _suffix(),
            enabledBorder: _border(const Color(0xFFE2E8F0)),
            focusedBorder: _border(AuthPalette.teal, width: 1.5),
            border: _border(const Color(0xFFE2E8F0)),
            disabledBorder: _border(const Color(0xFFEDF2F7)),
          ),
        ),
      ],
    );
  }

  Widget? _suffix() {
    if (widget.obscure) {
      return IconButton(
        tooltip: _obscured ? 'Show password' : 'Hide password',
        icon: Icon(
          _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 20,
          // Was #BBBBBB (1.9:1), close to invisible. Controls need 3:1.
          color: AuthPalette.fieldIcon,
        ),
        onPressed: () => setState(() => _obscured = !_obscured),
      );
    }
    if (widget.showCheckWhenFilled && widget.controller.text.isNotEmpty) {
      return const Icon(Icons.check_circle, size: 20, color: AuthPalette.teal);
    }
    return null;
  }

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
}
