import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import 'widgets/profile_widgets.dart';

/// Help & Support screen providing support channels (Email, Phone/WhatsApp)
/// and frequently asked questions for users.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  Future<void> _launchEmail(BuildContext context) async {
    final uri = Uri.parse('mailto:support@afyasmart.app?subject=AfyaSmart%20Support%20Request');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email client. Email us at support@afyasmart.app')),
        );
      }
    }
  }

  Future<void> _launchWhatsApp(BuildContext context) async {
    final uri = Uri.parse('https://wa.me/254700000000?text=Hello%20AfyaSmart%20Support');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProfileSubpage(
      title: 'Help & Support',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          const _HeaderBanner(),
          const SizedBox(height: 20),
          const Text(
            'Contact Channels',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppPalette.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          _ContactCard(
            icon: Icons.mail_outline,
            title: 'Email Support',
            subtitle: 'support@afyasmart.app',
            onTap: () => _launchEmail(context),
          ),
          const SizedBox(height: 10),
          _ContactCard(
            icon: Icons.chat_bubble_outline,
            title: 'WhatsApp Support',
            subtitle: '+254 700 000 000 · Fast responses',
            onTap: () => _launchWhatsApp(context),
          ),
          const SizedBox(height: 24),
          const Text(
            'Frequently Asked Questions',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppPalette.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          const _FaqItem(
            question: 'How does AI symptom analysis work?',
            answer:
                'AfyaSmart AI asks guided questions regarding your symptoms and health concerns. '
                'It then compares your inputs against medical guidelines to suggest probable conditions, '
                'urgency levels, and recommendations for next steps.',
          ),
          const SizedBox(height: 10),
          const _FaqItem(
            question: 'How do I upgrade my subscription via M-Pesa?',
            answer:
                'Go to Profile > Subscription Plan, select your preferred plan (e.g. Daily, Weekly, Monthly), '
                'and enter your M-Pesa phone number. An STK push prompt will be sent directly to your phone to enter your PIN.',
          ),
          const SizedBox(height: 10),
          const _FaqItem(
            question: 'What if my payment went through but status is pending?',
            answer:
                'Check Profile > Payment History to view all recorded transactions. '
                'If your M-Pesa account was debited, your subscription usually updates within 1 minute. '
                'If it remains pending, pull down on the Payment History screen to refresh, or reach out to our support team.',
          ),
          const SizedBox(height: 10),
          const _FaqItem(
            question: 'How do I find nearby doctors and pharmacies?',
            answer:
                'Use the navigation bar at the bottom to access Doctors, Pharmacy, or Map. '
                'You can view list details, operating hours, phone numbers, and location directions.',
          ),
          const SizedBox(height: 10),
          const _FaqItem(
            question: 'How does the Affiliate Program work?',
            answer:
                'Go to Profile > Affiliate Program to enroll. You will receive a unique referral link. '
                'Whenever someone signs up and subscribes using your link, you earn 30% commission, which you can withdraw to M-Pesa.',
          ),
        ],
      ),
    );
  }
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    return ProfileCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFFE0F2F1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.help_outline, size: 26, color: AppColors.brand),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How can we help you?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textStrong,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'We are here to assist with health queries and subscriptions.',
                  style: TextStyle(fontSize: 12, color: AppPalette.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppPalette.hairline),
      ),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0xFFE0F2F1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: AppColors.brand),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppPalette.textStrong,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppPalette.textMuted),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          size: 20,
          color: AppPalette.textMuted,
        ),
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  const _FaqItem({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.hairline),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: const Border(),
        title: Text(
          question,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppPalette.textStrong,
          ),
        ),
        children: [
          Text(
            answer,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppPalette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
