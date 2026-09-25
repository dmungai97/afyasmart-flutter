import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../core/router.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../models/catalogue.dart';
import '../../state/providers.dart';
import 'widgets/catalogue_widgets.dart';

/// Port of src/user/screens/DrugsScreen.tsx.
class DrugsScreen extends ConsumerStatefulWidget {
  const DrugsScreen({super.key});

  @override
  ConsumerState<DrugsScreen> createState() => _DrugsScreenState();
}

/// Where a result came from. The OpenFDA fallback is labelled in the UI so a
/// user can tell curated local data from an external label.
enum DrugSource { local, fda }

const _categories = [
  'All',
  'Antibiotic',
  'Analgesic',
  'Antidiabetic',
  'NSAID',
  'Antimalarial',
  'Other',
];

/// Offered on the empty state so the first search is one tap. Common
/// medicines in Kenya, spanning the category chips.
const _popular = ['Paracetamol', 'Amoxicillin', 'Ibuprofen', 'Metformin', 'Artemether'];

const _surface = Color(0xFFF2F4F5);

/// Inferred from the dosage text — the catalogue has no form column.
String _formType(Drug d) {
  final text = '${d.dosage}${d.uses}'.toLowerCase();
  if (text.contains('capsule')) return 'Capsule';
  if (text.contains('syrup')) return 'Syrup';
  if (text.contains('inject')) return 'Injection';
  return 'Tablet';
}

class _DrugsScreenState extends ConsumerState<DrugsScreen> {
  final _query = TextEditingController();

  List<Drug> _results = const [];
  DrugSource? _source;
  String _activeTab = 'All';
  bool _loading = false;
  bool _searched = false;
  bool _locked = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search([String? preset]) async {
    if (preset != null) {
      _query.text = preset;
      FocusScope.of(context).unfocus();
    }
    final q = _query.text.trim();
    if (q.isEmpty) return;

    setState(() {
      _loading = true;
      _searched = true;
      _source = null;
      _locked = false;
    });

    try {
      final local = await ref.read(catalogueServiceProvider).searchDrugs(q);

      if (local.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _results = local;
          _source = DrugSource.local;
        });
      } else {
        await _fallbackToFda(q);
      }
    } on PaywallException {
      // Deliberately NOT falling through to OpenFDA here.
      //
      // The RN screen caught every error and fell back to OpenFDA, so a
      // permission failure would still return drug data — the paywall leaking
      // through an external API. The route guard normally stops a
      // non-subscriber reaching this screen at all, but defence in depth is
      // cheap and a silent leak is not.
      if (!mounted) return;
      setState(() {
        _results = const [];
        _locked = true;
      });
    } on Exception {
      // A genuine backend failure still falls back, as before.
      await _fallbackToFda(q);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fallbackToFda(String query) async {
    final results = await _searchOpenFda(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _source = results.isEmpty ? null : DrugSource.fda;
    });
  }

  /// OpenFDA's public label API. No key required, and no auth is sent — this
  /// is a public reference lookup, not user data.
  Future<List<Drug>> _searchOpenFda(String query) async {
    try {
      final encoded = Uri.encodeComponent(query);
      final uri = Uri.parse(
        'https://api.fda.gov/drug/label.json'
        '?search=openfda.generic_name:"$encoded"+openfda.brand_name:"$encoded"'
        '&limit=10',
      );

      final response = await http.get(uri);
      if (response.statusCode != 200) return const [];

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return const [];

      final results = (body['results'] as List?) ?? const [];

      String? first(Map<String, dynamic> r, String key) {
        final list = (r['openfda'] as Map?)?[key] as List?;
        return list == null || list.isEmpty ? null : list.first.toString();
      }

      String clip(Object? field, String fallback) {
        final list = field as List?;
        if (list == null || list.isEmpty) return fallback;
        final text = list.first.toString();
        return text.length > 400 ? text.substring(0, 400) : text;
      }

      return [
        for (var i = 0; i < results.length; i++)
          if (results[i] case final Map<String, dynamic> r)
            Drug(
              // Offset well clear of the catalogue's identity ids so the two
              // sources can never collide in a list key.
              id: 9000 + i,
              name: first(r, 'brand_name') ?? first(r, 'generic_name') ?? query,
              genericName: first(r, 'generic_name') ?? '',
              category: first(r, 'pharm_class_epc') ?? 'Other',
              uses: clip(r['indications_and_usage'], 'See full label.'),
              dosage: clip(r['dosage_and_administration'], 'See full label.'),
              sideEffects: clip(r['adverse_reactions'], 'Not listed.'),
              // OpenFDA labels do not expose these as booleans, so they are
              // reported as unsafe rather than guessed.
              pregnancySafe: false,
              alcoholSafe: false,
              lactationSafe: false,
              prescriptionRequired: first(r, 'product_type') == 'OTC'
                  ? 'No'
                  : 'Yes',
            ),
      ];
    } on Exception {
      return const [];
    }
  }

  List<Drug> get _filtered => _activeTab == 'All'
      ? _results
      : _results
            .where(
              (d) => d.category.toLowerCase().contains(_activeTab.toLowerCase()),
            )
            .toList();

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            if (_searched && !_locked) _categoryChips(),
            const Divider(height: 1, color: AppPalette.hairline),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: EdgeInsets.fromLTRB(
      8,
      MediaQuery.viewPaddingOf(context).top + 4,
      16,
      12,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go(Routes.home),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: AppPalette.textStrong,
              ),
            ),
            const SizedBox(width: 2),
            const Text(
              'Medicines',
              style: TextStyle(
                color: AppPalette.textStrong,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            onChanged: (_) => setState(() {}),
            cursorColor: AppColors.brand,
            style: const TextStyle(fontSize: 15, color: AppPalette.textStrong),
            decoration: InputDecoration(
              hintText: 'Search by name, e.g. paracetamol',
              hintStyle: const TextStyle(color: AppPalette.textMuted),
              isDense: true,
              filled: true,
              fillColor: _surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 20,
                color: AppPalette.textMuted,
              ),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppPalette.textMuted,
                      ),
                      onPressed: () => setState(() {
                        _query.clear();
                        _results = const [];
                        _searched = false;
                        _source = null;
                        _locked = false;
                        _activeTab = 'All';
                      }),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  /// Only shown once there are results to filter; before a search they
  /// would filter nothing.
  Widget _categoryChips() => SizedBox(
    height: 44,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      children: [
        for (final cat in _categories)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _Pill(
              label: cat,
              selected: _activeTab == cat,
              onTap: () => setState(() => _activeTab = cat),
            ),
          ),
      ],
    ),
  );

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.brand,
          ),
        ),
      );
    }

    if (_locked) {
      return const SingleChildScrollView(
        child: CatalogueEmpty(
          locked: true,
          lockedMessage: 'Subscribe to search the drug database',
          emptyMessage: '',
          emptyIcon: '',
        ),
      );
    }

    if (!_searched) return _intro();

    final filtered = _filtered;
    if (filtered.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No medicines found',
        message: _activeTab == 'All'
            ? 'Check the spelling, or try the generic name.'
            : 'Nothing in $_activeTab. Try another category.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: filtered.length + (_source == DrugSource.fda ? 1 : 0),
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 20, color: AppPalette.hairline),
      itemBuilder: (_, i) {
        if (_source == DrugSource.fda) {
          if (i == 0) return _fdaNotice();
          return _row(filtered[i - 1]);
        }
        return _row(filtered[i]);
      },
    );
  }

  /// Before any search: what this is, plus a few one-tap searches.
  Widget _intro() => ListView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
    children: [
      const Text(
        'Look up a medicine',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppPalette.textStrong,
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'See what it treats, how it is taken, side effects, and whether it is '
        'safe in pregnancy, while breastfeeding or with alcohol.',
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: AppPalette.textMuted,
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'COMMON SEARCHES',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: AppPalette.textMuted,
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final name in _popular)
            _Pill(label: name, onTap: () => _search(name)),
        ],
      ),
    ],
  );

  Widget _fdaNotice() => const Padding(
    padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 15, color: AppPalette.textMuted),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Not in our catalogue. Showing results from the US FDA label '
            'database, which may use US brand names.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppPalette.textMuted,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _row(Drug d) => InkWell(
    onTap: () => _showDetail(d),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (d.genericName.isNotEmpty &&
                        d.genericName.toLowerCase() != d.name.toLowerCase())
                      d.genericName,
                    _formType(d),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppPalette.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  d.uses,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppPalette.textBody,
                  ),
                ),
                const SizedBox(height: 8),
                _SafetyLine(d),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppPalette.textMuted,
          ),
        ],
      ),
    ),
  );

  void _showDetail(Drug d) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppPalette.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              d.name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppPalette.textStrong,
              ),
            ),
            if (d.genericName.isNotEmpty)
              Text(
                d.genericName,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppPalette.textMuted,
                ),
              ),
            const SizedBox(height: 16),
            _section('Category', d.category),
            _section('Uses', d.uses),
            _section('Dosage', d.dosage),
            _section('Side effects', d.sideEffects),
            _section(
              'Prescription required',
              d.prescriptionRequired == 'No' ? 'No — over the counter' : 'Yes',
            ),
            const SizedBox(height: 2),
            Text(
              'SAFETY',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppPalette.textMuted,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            _SafetyLine(d),
            const SizedBox(height: 20),
            const Text(
              'Always confirm dosage with a pharmacist or doctor before '
              'taking any medicine.',
              style: TextStyle(
                fontSize: 11,
                color: AppPalette.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppPalette.textMuted,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            color: AppPalette.textBody,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

/// Small rounded label used for category filters and common searches.
/// Selected: teal on light teal. Otherwise: plain text on light grey.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap, this.selected = false});

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFFE0F2F1) : _surface,
    shape: const StadiumBorder(),
    child: InkWell(
      onTap: onTap,
      customBorder: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.brand : AppPalette.textBody,
          ),
        ),
      ),
    ),
  );
}

/// The three safety flags as quiet text with a small tick or cross, instead
/// of three coloured pills per row.
class _SafetyLine extends StatelessWidget {
  const _SafetyLine(this.drug);

  final Drug drug;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 4,
    children: [
      _flag('Pregnancy', drug.pregnancySafe),
      _flag('Breastfeeding', drug.lactationSafe),
      _flag('Alcohol', drug.alcoholSafe),
    ],
  );

  static Widget _flag(String label, bool safe) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        safe ? Icons.check_rounded : Icons.close_rounded,
        size: 14,
        color: safe ? AppPalette.green : AppPalette.red,
      ),
      const SizedBox(width: 3),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppPalette.textMuted),
      ),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(40, 72, 40, 24),
    children: [
      Icon(icon, size: 32, color: AppPalette.textMuted),
      const SizedBox(height: 12),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppPalette.textStrong,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          height: 1.5,
          color: AppPalette.textMuted,
        ),
      ),
    ],
  );
}
