import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'widgets/profile_widgets.dart';

/// Terms & Conditions screen outlining user agreements, medical disclaimers,
/// subscription billing terms, and affiliate guidelines.
class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfileSubpage(
      title: 'Terms & Conditions',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: const [
          _MedicalDisclaimerBanner(),
          SizedBox(height: 16),
          _TermsSection(
            icon: Icons.article_outlined,
            title: '1. Acceptance of Terms',
            content:
                'By accessing or using the AfyaSmart application, you agree to be bound by these Terms and Conditions. '
                'If you do not agree to these terms, you may not use our services.',
          ),
          SizedBox(height: 14),
          _TermsSection(
            icon: Icons.warning_amber_outlined,
            title: '2. Medical & AI Disclaimer',
            content:
                'AfyaSmart provides artificial intelligence-assisted symptom evaluation and health information for informational purposes only.\n\n'
                '• Not Medical Advice: Content provided by AfyaSmart is not a substitute for professional medical advice, diagnosis, or treatment.\n'
                '• Emergency Services: If you are experiencing a medical emergency, call emergency services or go to the nearest hospital immediately.',
          ),
          SizedBox(height: 14),
          _TermsSection(
            icon: Icons.credit_card_outlined,
            title: '3. Subscriptions & M-Pesa Payments',
            content:
                'Certain features require an active paid subscription:\n\n'
                '• Payment Processing: Payments are made securely via M-Pesa. Subscription plans grant access for the duration specified.\n'
                '• Non-Refundable: Subscription fees are non-refundable once activated.\n'
                '• Account Status: Active subscriptions apply immediately to your account across all supported devices.',
          ),
          SizedBox(height: 14),
          _TermsSection(
            icon: Icons.person_outline,
            title: '4. User Accounts & Security',
            content:
                'You are responsible for maintaining the confidentiality of your account login credentials. '
                'You agree to notify AfyaSmart immediately of any unauthorized use of your account.',
          ),
          SizedBox(height: 14),
          _TermsSection(
            icon: Icons.share_outlined,
            title: '5. Affiliate Program Terms',
            content:
                'Users participating in the AfyaSmart Affiliate Program earn commissions on successful referral subscriptions. '
                'Fraudulent, self-referral, or misleading practices will result in account suspension and forfeiture of earnings.',
          ),
          SizedBox(height: 14),
          _TermsSection(
            icon: Icons.gavel_outlined,
            title: '6. Limitation of Liability',
            content:
                'AfyaSmart and its affiliates shall not be liable for any indirect, incidental, or consequential damages arising from your use of the application or reliance on AI health information.',
          ),
        ],
      ),
    );
  }
}

class _MedicalDisclaimerBanner extends StatelessWidget {
  const _MedicalDisclaimerBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.orangeBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.orange),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.medical_services_outlined, size: 24, color: AppPalette.orange),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Important Medical Notice',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.orange,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'AfyaSmart AI provides general health insights and is NOT a replacement for a licensed doctor or emergency healthcare provider.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppPalette.textStrong,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TermsSection extends StatelessWidget {
  const _TermsSection({
    required this.icon,
    required this.title,
    required this.content,
  });

  final IconData icon;
  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.brand),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppPalette.textStrong,
            ),
          ),
        ],
      ),
    );
  }
}
