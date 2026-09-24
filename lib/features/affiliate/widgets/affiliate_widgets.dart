import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';

/// Shared chrome for the affiliate tabs.

String formatKes(num value) => 'Ksh ${value.toStringAsFixed(0)}';

String formatMoment(DateTime? value) {
  if (value == null) return 'Recent';
  final date = value.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final day = date.day.toString().padLeft(2, '0');
  final month = months[(date.month - 1).clamp(0, 11)];
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day $month ${date.year}, $hour:$minute';
}

class AffiliateHeader extends StatelessWidget {
  const AffiliateHeader({required this.title, this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: AppColors.brand,
    padding: EdgeInsets.fromLTRB(
      20,
      MediaQuery.viewPaddingOf(context).top + 16,
      20,
      18,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ],
    ),
  );
}

class AffiliateCard extends StatelessWidget {
  const AffiliateCard({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppPalette.hairline),
    ),
    child: child,
  );
}

class AffiliateEmpty extends StatelessWidget {
  const AffiliateEmpty({required this.icon, required this.message, super.key});

  final String icon;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
    child: Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 32)),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppPalette.textMuted,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

/// A label/value pair used across the balance and stat rows.
class AffiliateStat extends StatelessWidget {
  const AffiliateStat({
    required this.label,
    required this.value,
    this.color,
    super.key,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: color ?? AppPalette.textStrong,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppPalette.textMuted),
      ),
    ],
  );
}
