import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

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

/// Inferred from the dosage text — the catalogue has no form column.
String _formType(Drug d) {
  final text = '${d.dosage}${d.uses}'.toLowerCase();
  if (text.contains('capsule')) return 'Capsule';
  if (text.contains('syrup')) return 'Syrup';
  if (text.contains('inject')) return 'Injection';
  return 'Tablet';
}

const _formColors = {
  'Tablet': (bg: Color(0xFFE8F4FE), fg: Color(0xFF1565C0)),
  'Capsule': (bg: Color(0xFFF3E8FF), fg: Color(0xFF6A1B9A)),
  'Syrup': (bg: Color(0xFFE8F5E9), fg: Color(0xFF2E7D32)),
  'Injection': (bg: Color(0xFFFFF3E0), fg: Color(0xFFE65100)),
};

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

  Future<void> _search() async {
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
    return Container(
      color: const Color(0xFFF5F7FA),
      child: Column(
        children: [
          _header(),
          _categoryChips(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _header() => Container(
    color: AppColors.brand,
    padding: EdgeInsets.fromLTRB(
      20,
      MediaQuery.viewPaddingOf(context).top + 16,
      20,
      18,
    ),
    child: Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Drugs Database',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Search medicines & info',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.medical_services,
                size: 22,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search medicine...',
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.cancel, size: 18),
                    onPressed: () => setState(() {
                      _query.clear();
                      _results = const [];
                      _searched = false;
                      _source = null;
                      _locked = false;
                    }),
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _categoryChips() => SizedBox(
    height: 46,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        for (final cat in _categories)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(cat),
              selected: _activeTab == cat,
              onSelected: (_) => setState(() => _activeTab = cat),
              selectedColor: AppColors.brand,
              backgroundColor: Colors.white,
              side: const BorderSide(color: AppPalette.hairline),
              showCheckmark: false,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _activeTab == cat ? Colors.white : AppPalette.textBody,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.brand));
    }

    if (_locked) {
      return const SingleChildScrollView(
        child: CatalogueEmpty(
          locked: true,
          lockedMessage: 'Subscribe to search the drug database',
          emptyMessage: '',
          emptyIcon: '💊',
        ),
      );
    }

    if (!_searched) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🔍', style: TextStyle(fontSize: 34)),
              SizedBox(height: 12),
              Text(
                'Search for a medicine to see its uses, dosage and safety '
                'information.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppPalette.textMuted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filtered;
    if (filtered.isEmpty) {
      return const SingleChildScrollView(
        child: CatalogueEmpty(
          locked: false,
          lockedMessage: '',
          emptyMessage: 'No medicines found',
          emptyIcon: '💊',
        ),
      );
    }

    return Column(
      children: [
        if (_source == DrugSource.fda) _fdaNotice(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: filtered.length,
            itemBuilder: (_, i) => _card(filtered[i]),
          ),
        ),
      ],
    );
  }

  Widget _fdaNotice() => Container(
    margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppPalette.orangeBg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Row(
      children: [
        Icon(Icons.info_outline, size: 15, color: AppPalette.orange),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Not in our catalogue — showing results from the OpenFDA label '
            'database.',
            style: TextStyle(fontSize: 11, color: AppPalette.orange),
          ),
        ),
      ],
    ),
  );

  Widget _card(Drug d) {
    final form = _formType(d);
    final colors = _formColors[form]!;

    return CatalogueCard(
      onTap: () => _showDetail(d),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  d.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textStrong,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.bg,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  form,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: colors.fg,
                  ),
                ),
              ),
            ],
          ),
          if (d.genericName.isNotEmpty)
            Text(
              d.genericName,
              style: const TextStyle(fontSize: 12, color: AppPalette.textMuted),
            ),
          const SizedBox(height: 6),
          Text(
            d.uses,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppPalette.textBody,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _safetyBadge('Pregnancy', d.pregnancySafe),
              _safetyBadge('Alcohol', d.alcoholSafe),
              _safetyBadge('Lactation', d.lactationSafe),
            ],
          ),
        ],
      ),
    );
  }

  Widget _safetyBadge(String label, bool safe) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: safe ? AppPalette.greenBg : AppPalette.redBg,
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    child: Text(
      '${safe ? '✓' : '✗'} $label',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: safe ? AppPalette.green : AppPalette.red,
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _safetyBadge('Pregnancy', d.pregnancySafe),
                _safetyBadge('Alcohol', d.alcoholSafe),
                _safetyBadge('Lactation', d.lactationSafe),
              ],
            ),
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
