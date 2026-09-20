import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router.dart';
import '../../../core/theme.dart';

/// Pieces shared by the doctors, pharmacy and drugs screens, which are the
/// same shape in the RN app: a teal header, a search row, a list of cards and
/// a detail sheet — each with its own copy of the styles.

class CatalogueHeader extends StatelessWidget {
  const CatalogueHeader({required this.title, required this.subtitle, super.key});

  final String title;
  final String subtitle;

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
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    ),
  );
}

class CatalogueSearchRow extends StatelessWidget {
  const CatalogueSearchRow({
    required this.controller,
    required this.hint,
    required this.onSearch,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            cursorColor: AppColors.brand,
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppPalette.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppPalette.hairline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.brand),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(
          onPressed: onSearch,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'Search',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

/// The empty state.
///
/// [locked] distinguishes "you are not subscribed" from "nothing matched".
/// That distinction is the whole reason PaywallException exists: Postgres RLS
/// returns zero rows to a non-subscriber rather than an error, so without an
/// explicit signal these two cases would be indistinguishable and the user
/// would be told there are no doctors rather than that they need to subscribe.
class CatalogueEmpty extends StatelessWidget {
  const CatalogueEmpty({
    required this.locked,
    required this.lockedMessage,
    required this.emptyMessage,
    required this.emptyIcon,
    this.onClearFilters,
    super.key,
  });

  final bool locked;
  final String lockedMessage;
  final String emptyMessage;
  final String emptyIcon;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
    child: Column(
      children: [
        Text(
          locked ? '🔒' : emptyIcon,
          style: const TextStyle(fontSize: 34),
        ),
        const SizedBox(height: 12),
        Text(
          locked ? lockedMessage : emptyMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppPalette.textMuted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        if (locked)
          FilledButton(
            onPressed: () => context.go(Routes.subscription),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: const StadiumBorder(),
            ),
            child: const Text(
              'View plans',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          )
        else if (onClearFilters != null)
          OutlinedButton(
            onPressed: onClearFilters,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brand,
              side: const BorderSide(color: AppColors.brand),
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: const StadiumBorder(),
            ),
            child: const Text('Clear filters', style: TextStyle(fontSize: 13)),
          ),
      ],
    ),
  );
}

class CatalogueCard extends StatelessWidget {
  const CatalogueCard({required this.child, this.onTap, super.key});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.hairline),
          ),
          child: child,
        ),
      ),
    ),
  );
}

/// A filter chip row. Shows shimmer-free skeleton pills while the values
/// load, matching the RN screens' placeholder chips.
class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    required this.label,
    required this.values,
    required this.active,
    required this.onPick,
    required this.loading,
    super.key,
  });

  final String label;
  final List<String> values;
  final String? active;
  final void Function(String) onPick;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (!loading && values.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppPalette.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: loading
                ? [
                    for (final w in <double>[110, 95, 120, 100, 130, 105])
                      Container(
                        width: w,
                        height: 32,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: AppPalette.hairline,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                      ),
                  ]
                : [
                    for (final value in values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(value),
                          selected: active == value,
                          onSelected: (_) => onPick(value),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: active == value
                                ? Colors.white
                                : AppPalette.textBody,
                          ),
                          selectedColor: AppColors.brand,
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: AppPalette.hairline),
                          showCheckmark: false,
                        ),
                      ),
                  ],
          ),
        ),
      ],
    );
  }
}
