import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../services/affiliate_service.dart';
import '../../state/affiliate_controller.dart';
import 'widgets/affiliate_widgets.dart';

/// Port of affiliate/screens/AffiliateDashboardScreen.tsx.
class AffiliateDashboardScreen extends ConsumerWidget {
  const AffiliateDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(affiliateControllerProvider).value ??
        const AffiliateSummary.empty();

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: () => ref.read(affiliateControllerProvider.notifier).reload(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          _balanceCard(context, data),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              children: [
                _performanceCard(data),
                const SizedBox(height: 14),
                _periodCard(data),
                const SizedBox(height: 14),
                _shareCard(context, data.code),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceCard(BuildContext context, AffiliateSummary data) => Container(
    width: double.infinity,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.brand, AppColors.accent],
      ),
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      boxShadow: [
        BoxShadow(
          color: Color(0x1A000000),
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ],
    ),
    padding: EdgeInsets.fromLTRB(
      24,
      MediaQuery.viewPaddingOf(context).top + 16,
      24,
      32,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              onTap: () => context.go(Routes.profile),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 16, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'Back to Profile',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _copyCode(context, data.code),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ID: ${data.code}',
                      style: const TextStyle(
                        color: Colors.white, 
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.copy, size: 14, color: Colors.white),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Text(
          'Available balance',
          style: TextStyle(
            color: Colors.white70, 
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          formatKes(data.availableBalance),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 38,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _whiteStat(
                'Pending',
                formatKes(data.pendingBalance),
              ),
            ),
            Expanded(
              child: _whiteStat(
                'Total earned',
                formatKes(data.totalEarned),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => context.go(Routes.affiliateWithdraw),
          icon: const Icon(Icons.account_balance_wallet, size: 18),
          label: const Text(
            'Withdraw earnings',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.brand,
            elevation: 2,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _whiteStat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    ],
  );

  Widget _performanceCard(AffiliateSummary data) => AffiliateCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Performance',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppPalette.textStrong,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: AffiliateStat(
                label: 'Referrals',
                value: '${data.referralsCount}',
              ),
            ),
            Expanded(
              child: AffiliateStat(
                label: 'Subscribed',
                value: '${data.activeUsersCount}',
                color: AppPalette.green,
              ),
            ),
            Expanded(
              child: AffiliateStat(
                label: 'Conversion',
                value: '${data.conversionRate}%',
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _periodCard(AffiliateSummary data) => AffiliateCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Earnings',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppPalette.textStrong,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: AffiliateStat(
                label: 'Today',
                value: formatKes(data.earningsToday),
              ),
            ),
            Expanded(
              child: AffiliateStat(
                label: 'This week',
                value: formatKes(data.earningsThisWeek),
              ),
            ),
            Expanded(
              child: AffiliateStat(
                label: 'This month',
                value: formatKes(data.earningsThisMonth),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _shareCard(BuildContext context, String code) {
    final link = 'https://afyasmart.app/register?ref=$code';

    return AffiliateCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your referral link & code',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppPalette.textStrong,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Anyone who registers with your link earns you 30% of every '
            'subscription they pay for.',
            style: TextStyle(
              fontSize: 12,
              color: AppPalette.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppPalette.hairline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        code,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: AppColors.brand,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        link,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppPalette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _copyLink(context, link),
                  icon: const Icon(Icons.copy, size: 18),
                  color: AppColors.brand,
                  tooltip: 'Copy Link',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _shareWhatsApp(context, link),
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text(
                    'Share to WhatsApp',
                    textAlign: TextAlign.center,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE6F4F1),
                    foregroundColor: const Color(0xFF006D5B),
                    elevation: 0,
                    minimumSize: const Size.fromHeight(46),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyCode(context, code),
                  icon: const Icon(Icons.code, size: 16),
                  label: const Text(
                    'Copy Code',
                    textAlign: TextAlign.center,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppPalette.textStrong,
                    side: const BorderSide(color: AppPalette.hairline),
                    minimumSize: const Size.fromHeight(46),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copyCode(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text('Referral code $code copied.')),
      );
  }

  Future<void> _copyLink(BuildContext context, String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('Referral link copied to clipboard.')),
      );
  }

  Future<void> _shareWhatsApp(BuildContext context, String link) async {
    final message = Uri.encodeComponent(
      'Join AfyaSmart for AI health insights and doctor consultations! '
      'Register using my referral link: $link',
    );
    final uri = Uri.parse('https://wa.me/?text=$message');

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        await _copyLink(context, link);
      }
    }
  }
}
