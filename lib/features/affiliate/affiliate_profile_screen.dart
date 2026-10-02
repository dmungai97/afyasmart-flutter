import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../services/affiliate_service.dart';
import '../../state/affiliate_controller.dart';
import '../../state/auth_controller.dart';
import 'widgets/affiliate_widgets.dart';

/// Port of affiliate/screens/AffiliateProfileScreen.tsx.
class AffiliateProfileScreen extends ConsumerWidget {
  const AffiliateProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(affiliateControllerProvider).value ??
        const AffiliateSummary.empty();
    final user = ref.watch(currentUserProvider);

    return Column(
      children: [
        const AffiliateHeader(title: 'Affiliate profile'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              AffiliateCard(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.brand,
                      child: Text(
                        (user?.name.isNotEmpty ?? false)
                            ? user!.name[0].toUpperCase()
                            : 'A',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.name ?? 'Affiliate',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.textStrong,
                            ),
                          ),
                          Text(
                            user?.email ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppPalette.textMuted,
                            ),
                          ),
                          Text(
                            'Affiliate since ${formatMoment(data.since)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppPalette.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _ShareCard(code: data.code),
              const SizedBox(height: 14),
              AffiliateCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'How it works',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textStrong,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final line in const [
                      'Share your code with anyone who might use AfyaSmart.',
                      'They enter it when they register.',
                      'You earn 30% of every subscription they pay for.',
                      'Commissions are held for 7 days, then become '
                          'available to withdraw.',
                      'Withdraw to M-Pesa once you have at least Ksh 100.',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              size: 15,
                              color: AppColors.brand,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                line,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppPalette.textBody,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => context.go(Routes.home),
                icon: const Icon(Icons.arrow_back, size: 17),
                label: const Text('Back to AfyaSmart'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brand,
                  side: const BorderSide(color: AppColors.brand),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(height: 12),
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
