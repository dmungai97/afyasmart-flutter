import 'package:flutter/material.dart';

/// The teal branded backdrop shared by login and register.
///
/// In the RN screens this was ~40 absolutely-positioned `View`s inlined into
/// each screen (decorative circles, a column of faint medical crosses and a
/// heartbeat rule), duplicated between LoginScreen.tsx and RegisterScreen.tsx.
/// Extracting it means the two cannot drift apart, and the drawing happens on
/// a single canvas rather than in dozens of layers.
abstract final class AuthPalette {
  static const teal = Color(0xFF005454);
  static const tealDark = Color(0xFF004F50);
  static const fieldIcon = Color(0xFF718096);
  static const hint = Color(0xFF9AA7A7);
}

class AuthBackdrop extends StatelessWidget {
  const AuthBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AuthPalette.tealDark, AuthPalette.teal],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _BackdropPainter()),
          ),
          child,
        ],
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white;

    // Three soft circles bleeding off the top edge, matching the RN
    // positions and opacities.
    void circle(double diameter, double left, double top, double opacity) {
      canvas.drawCircle(
        Offset(left + diameter / 2, top + diameter / 2),
        diameter / 2,
        white..color = Colors.white.withValues(alpha: opacity),
      );
    }

    circle(320, size.width - 240, -80, 0.12);
    circle(200, -60, 60, 0.08);
    circle(150, size.width - 170, 180, 0.06);

    // A column of faint medical crosses, fading in down the screen.
    for (var i = 0; i < 6; i++) {
      final top = 40 + i * 60.0;
      final left = 20 + (i % 2) * 80.0;
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: 0.04 + i * 0.01);

      // Vertical bar, then horizontal, forming the cross.
      canvas.drawRect(Rect.fromLTWH(left + 8, top, 4, 20), paint);
      canvas.drawRect(Rect.fromLTWH(left, top + 8, 20, 4), paint);
    }

    // The heartbeat rule across the lower third.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final y = size.height * 0.34;
    final path = Path()..moveTo(0, y);
    final step = size.width / 8;
    for (var i = 0; i < 8; i++) {
      final x = step * i;
      path
        ..lineTo(x + step * 0.3, y)
        ..lineTo(x + step * 0.4, y - 12)
        ..lineTo(x + step * 0.5, y + 12)
        ..lineTo(x + step * 0.6, y);
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The ringed logo mark: two concentric rings around a white cross, with the
/// small pulse dot offset to the corner.
class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(104, 0.12),
          _ring(84, 0.18),
          Container(
            width: 62,
            height: 62,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add, color: AuthPalette.teal, size: 36),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF7FE3C1),
                shape: BoxShape.circle,
                border: Border.all(color: AuthPalette.teal, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(double size, double opacity) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: opacity),
    ),
  );
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
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2D3748),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          enabled: widget.enabled,
          keyboardType: widget.keyboardType,
          obscureText: _obscured,
          autocorrect: false,
          textInputAction: widget.textInputAction,
          onSubmitted: (_) => widget.onSubmitted?.call(),
          cursorColor: AuthPalette.teal,
          style: TextStyle(
            fontSize: 15,
            color: widget.enabled
                ? const Color(0xFF1A202C)
                : AuthPalette.hint,
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
        icon: Icon(
          _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 20,
          color: const Color(0xFFBBBBBB),
        ),
        onPressed: () => setState(() => _obscured = !_obscured),
      );
    }
    if (widget.showCheckWhenFilled && widget.controller.text.isNotEmpty) {
      return const Icon(
        Icons.check_circle,
        size: 20,
        color: AuthPalette.teal,
      );
    }
    return null;
  }

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
}
