import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../models/catalogue.dart';
import '../../state/providers.dart';
import 'widgets/catalogue_widgets.dart';

/// Port of src/user/screens/PharmacyScreen.tsx.
class PharmacyScreen extends ConsumerStatefulWidget {
  const PharmacyScreen({super.key});

  @override
  ConsumerState<PharmacyScreen> createState() => _PharmacyScreenState();
}

class _PharmacyScreenState extends ConsumerState<PharmacyScreen> {
  final _search = TextEditingController();

  List<Pharmacy> _pharmacies = const [];
  bool _loading = true;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load([String? query]) async {
    setState(() => _loading = true);
    try {
      final results = await ref
          .read(catalogueServiceProvider)
          .pharmacies(search: query);
      if (!mounted) return;
      setState(() {
        _pharmacies = results;
        _locked = false;
      });
    } on PaywallException {
      if (!mounted) return;
      setState(() {
        _pharmacies = const [];
        _locked = true;
      });
    } on Exception {
      if (!mounted) return;
      setState(() => _pharmacies = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: Column(
        children: [
          const CatalogueHeader(
            title: 'Pharmacy Listings',
            subtitle: 'Find pharmacies near you',
          ),
          CatalogueSearchRow(
            controller: _search,
            hint: 'Search pharmacy or location...',
            onSearch: () => _load(_search.text.trim()),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.brand),
                  )
                : _pharmacies.isEmpty
                ? SingleChildScrollView(
                    child: CatalogueEmpty(
                      locked: _locked,
                      lockedMessage: 'Subscribe to view pharmacies near you',
                      emptyMessage: 'No pharmacies found',
                      emptyIcon: '💊',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: _pharmacies.length,
                    itemBuilder: (_, i) => _card(_pharmacies[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(Pharmacy p) => CatalogueCard(
    onTap: () => _showDetail(p),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: const Text('🏪', style: TextStyle(fontSize: 22)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textStrong,
                      ),
                    ),
                  ),
                  _statusBadge(p),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                p.location,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppPalette.textMuted,
                ),
              ),
              if (p.openingHours.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  p.open24hrs ? 'Open 24 hours' : p.openingHours,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppPalette.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _statusBadge(Pharmacy p) {
    final open = p.open || p.open24hrs;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: open
            ? AppPalette.greenBg
            : AppPalette.redBg,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        open ? 'Open' : 'Closed',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: open ? AppPalette.green : AppPalette.red,
        ),
      ),
    );
  }

  void _showDetail(Pharmacy p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                p.name,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textStrong,
                ),
              ),
              const SizedBox(height: 14),
              _detailRow(Icons.location_on_outlined, p.address.isEmpty ? p.location : p.address),
              if (p.openingHours.isNotEmpty)
                _detailRow(
                  Icons.schedule,
                  p.open24hrs ? 'Open 24 hours' : p.openingHours,
                ),
              if (p.phone.isNotEmpty) _detailRow(Icons.phone_outlined, p.phone),
              if (p.email != null && p.email!.isNotEmpty)
                _detailRow(Icons.mail_outline, p.email!),
              const SizedBox(height: 18),
              if (p.phone.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _dial(p.phone),
                  icon: const Icon(Icons.phone, size: 18),
                  label: const Text('Call pharmacy'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.brand),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppPalette.textBody,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _dial(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the dialler.')),
      );
    }
  }
}
