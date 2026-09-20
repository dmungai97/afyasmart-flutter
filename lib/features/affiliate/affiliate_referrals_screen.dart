import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/affiliate_controller.dart';
import 'widgets/affiliate_widgets.dart';

/// Port of affiliate/screens/AffiliateReferralsScreen.tsx.
class AffiliateReferralsScreen extends ConsumerStatefulWidget {
  const AffiliateReferralsScreen({super.key});

  @override
  ConsumerState<AffiliateReferralsScreen> createState() =>
      _AffiliateReferralsScreenState();
}

enum _Filter { all, active, inactive }

class _AffiliateReferralsScreenState
    extends ConsumerState<AffiliateReferralsScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(affiliateControllerProvider).requireValue;

    final referrals = switch (_filter) {
      _Filter.all => data.referrals,
      _Filter.active => data.referrals.where((r) => r.active).toList(),
      _Filter.inactive => data.referrals.where((r) => !r.active).toList(),
    };

    return Column(
      children: [
        AffiliateHeader(
          title: 'Referrals',
          subtitle:
              '${data.referralsCount} signed up · '
              '${data.activeUsersCount} subscribed',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              _chip('All', _Filter.all, data.referralsCount),
              const SizedBox(width: 8),
              _chip('Subscribed', _Filter.active, data.activeUsersCount),
              const SizedBox(width: 8),
              _chip(
                'Not yet',
                _Filter.inactive,
                data.referralsCount - data.activeUsersCount,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.brand,
            onRefresh: () =>
                ref.read(affiliateControllerProvider.notifier).reload(),
            child: referrals.isEmpty
                ? ListView(
                    children: const [
                      AffiliateEmpty(
                        icon: '👥',
                        message:
                            'No referrals yet. Share your code and they will '
                            'appear here as soon as someone signs up with it.',
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: referrals.length,
                    itemBuilder: (_, i) {
                      final r = referrals[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AffiliateCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: AppColors.brand.withValues(
                                  alpha: 0.1,
                                ),
                                child: Text(
                                  r.name.isEmpty
                                      ? '?'
                                      : r.name[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.brand,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppPalette.textStrong,
                                      ),
                                    ),
                                    Text(
                                      'Joined ${formatMoment(r.joinedAt)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppPalette.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: r.active
                                      ? AppPalette.greenBg
                                      : AppPalette.hairline,
                                  borderRadius: BorderRadius.circular(
                                    Radii.pill,
                                  ),
                                ),
                                child: Text(
                                  r.active ? 'Subscribed' : 'Not yet',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: r.active
                                        ? AppPalette.green
                                        : AppPalette.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, _Filter value, int count) => ChoiceChip(
    label: Text('$label ($count)'),
    selected: _filter == value,
    onSelected: (_) => setState(() => _filter = value),
    selectedColor: AppColors.brand,
    backgroundColor: Colors.white,
    side: const BorderSide(color: AppPalette.hairline),
    showCheckmark: false,
    labelStyle: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: _filter == value ? Colors.white : AppPalette.textBody,
    ),
  );
}
