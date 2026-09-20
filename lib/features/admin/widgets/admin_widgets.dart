import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';

/// Shared chrome for the admin console.

final _money = NumberFormat.currency(
  locale: 'en_KE',
  symbol: 'Ksh ',
  decimalDigits: 0,
);
final _number = NumberFormat.decimalPattern('en');
final _dateTime = DateFormat('dd MMM, HH:mm', 'en');

String formatMoney(num value) => _money.format(value);
String formatNumber(num value) => _number.format(value);
String formatWhen(DateTime? value) =>
    value == null ? 'Recent' : _dateTime.format(value);

class AdminCard extends StatelessWidget {
  const AdminCard({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.md),
      border: Border.all(color: AppColors.rule),
    ),
    child: child,
  );
}

class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.value,
    this.sub,
    this.icon,
    super.key,
  });

  final String label;
  final String value;
  final String? sub;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => AdminCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: AppColors.ruleStrong),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkFaint,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(
            sub!,
            style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
          ),
        ],
      ],
    ),
  );
}

/// A status pill in the muted admin tints, rather than the saturated pastel
/// fills a generic dashboard would use.
class StatusPill extends StatelessWidget {
  const StatusPill({required this.label, required this.tone, super.key});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = switch (tone) {
      StatusTone.success => (
        AppColors.tintSuccessBg,
        AppColors.tintSuccessBorder,
        AppColors.success,
      ),
      StatusTone.warning => (
        AppColors.tintWarningBg,
        AppColors.tintWarningBorder,
        AppColors.accent,
      ),
      StatusTone.danger => (
        AppColors.tintDangerBg,
        AppColors.tintDangerBorder,
        AppColors.danger,
      ),
      StatusTone.neutral => (
        AppColors.paper,
        AppColors.tintNeutralBorder,
        AppColors.inkMuted,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

enum StatusTone { success, warning, danger, neutral }

StatusTone toneForStatus(String status) => switch (status) {
  'paid' => StatusTone.success,
  'pending' => StatusTone.warning,
  'failed' || 'rejected' => StatusTone.danger,
  'cancelled' => StatusTone.neutral,
  _ => StatusTone.neutral,
};

/// Consistent error panel for the admin screens. Riverpod's AsyncValue.when
/// already covers loading and data, so only the error arm needs sharing.
class AdminError extends StatelessWidget {
  const AdminError({required this.error, required this.onRetry, super.key});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: AppColors.danger),
          const SizedBox(height: 12),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class AdminLoading extends StatelessWidget {
  const AdminLoading({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(40),
      child: CircularProgressIndicator(color: AppColors.ruleStrong),
    ),
  );
}

class AdminEmpty extends StatelessWidget {
  const AdminEmpty({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
      ),
    ),
  );
}
