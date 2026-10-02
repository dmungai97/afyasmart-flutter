import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'widgets/profile_widgets.dart';

/// Privacy Policy screen providing comprehensive information on how user data,
/// medical symptom queries, and payment details are collected and protected.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfileSubpage(
      title: 'Privacy Policy',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: const [
          _LastUpdatedHeader(date: 'October 2024'),
          SizedBox(height: 16),
          _PolicySection(
            icon: Icons.shield_outlined,
            title: '1. Information We Collect',
            content:
                'AfyaSmart collects personal information required to deliver our health services:\n\n'
                '• Personal Details: Your name, email address, and phone number provided at registration.\n'
                '• Health & Symptom Data: Symptom descriptions and chat interactions submitted during AI health assessments.\n'
                '• Payment Information: Transaction references and phone numbers used for M-Pesa subscription payments.',
          ),
          SizedBox(height: 14),
          _PolicySection(
            icon: Icons.health_and_safety_outlined,
            title: '2. How We Use Your Data',
            content:
                'We use your information solely to deliver and improve health assistance:\n\n'
                '• To power AI-driven symptom analysis and health insights.\n'
                '• To manage your account, active subscriptions, and payment history.\n'
                '• To connect you with local doctors, pharmacies, and medical facilities.\n'
                '• To send critical account notifications and service updates.',
          ),
          SizedBox(height: 14),
          _PolicySection(
            icon: Icons.lock_outline,
            title: '3. Data Security & Confidentiality',
            content:
                'Your medical privacy is our top priority. We implement robust security protocols:\n\n'
                '• All data transmitted between your device and our servers is encrypted using standard TLS/SSL.\n'
                '• Health data is stored securely with industry-standard row-level security policies.\n'
                '• We do not sell, rent, or monetize your personal health information to third parties or advertisers.',
          ),
          SizedBox(height: 14),
          _PolicySection(
            icon: Icons.account_balance_wallet_outlined,
            title: '4. Third-Party Integrations',
            content:
                'AfyaSmart integrates with trusted external service providers strictly necessary for service delivery:\n\n'
                '• Safaricom M-Pesa: Processes payment transactions securely.\n'
                '• AI Language Models: Processes symptom queries to generate health recommendations without storing identifying credentials.\n'
                '• Mapping Services: Locates nearby healthcare facilities based on location permission.',
          ),
          SizedBox(height: 14),
          _PolicySection(
            icon: Icons.manage_accounts_outlined,
            title: '5. Your Rights & Controls',
            content:
                'You have full ownership of your personal information:\n\n'
                '• Profile Updates: Update your name and phone number at any time via Personal Information.\n'
                '• Account Deletion: You can permanently delete your account and all associated data directly from the Profile screen.',
          ),
          SizedBox(height: 14),
          _PolicySection(
            icon: Icons.mail_outline,
            title: '6. Contact Us',
            content:
                'If you have questions or concerns regarding our privacy practices, please reach out to our team at support@afyasmart.app.',
          ),
        ],
      ),
    );
  }
}

class _LastUpdatedHeader extends StatelessWidget {
  const _LastUpdatedHeader({required this.date});

  final String date;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2F1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 20, color: AppColors.brand),
          const SizedBox(width: 10),
          Text(
            'Last updated: $date',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.brand,
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({
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
