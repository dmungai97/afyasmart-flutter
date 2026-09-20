import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../state/affiliate_controller.dart';

/// Port of affiliate/screens/AffiliateEnrollScreen.tsx — the gate shown to
/// anyone who has not yet claimed a referral code.
class AffiliateEnrollScreen extends ConsumerStatefulWidget {
  const AffiliateEnrollScreen({super.key});

  @override
  ConsumerState<AffiliateEnrollScreen> createState() =>
      _AffiliateEnrollScreenState();
}

class _AffiliateEnrollScreenState extends ConsumerState<AffiliateEnrollScreen> {
  bool _loading = false;

  Future<void> _enroll() async {
    setState(() => _loading = true);
    final error = await ref.read(affiliateControllerProvider.notifier).enroll();
    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Could not enroll'),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    // On success the controller reloads and the shell swaps this screen for
    // the tabs; no navigation needed here.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.groups_outlined,
                  size: 52,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Become an AfyaSmart Affiliate',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF053E3E),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Get your own referral link and earn 30% commission every '
                'time someone you refer subscribes.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppPalette.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _enroll,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Get My Referral Code'),
                ),
              ),
              TextButton(
                onPressed: () => context.go(Routes.profile),
                child: const Text('Back to my profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
