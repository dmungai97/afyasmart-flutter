import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import 'widgets/vitals_rule.dart';

/// Port of src/onboarding/screens/WelcomeScreen.tsx.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

/// A few recognizable, real institutions to name-drop instead of a generic
/// "trusted by Kenyans" badge — filtered against the same seed data the app
/// ships with, so the names stay accurate as that data changes.
const _featuredHospitals = [
  'Kenyatta National Hospital',
  'Aga Khan University Hospital',
  'Nairobi Hospital',
];

const _features = [
  (
    icon: Icons.monitor_heart_outlined,
    title: 'Symptom checker',
    desc: 'Understand your health in 60 seconds',
  ),
  (
    icon: Icons.chat_bubble_outline,
    title: 'Health chat',
    desc: 'Talk through a concern any time of day',
  ),
  (
    icon: Icons.medical_services_outlined,
    title: 'Drug information',
    desc: 'Verify dosages, side effects and details',
  ),
  (
    icon: Icons.location_on_outlined,
    title: 'Local services',
    desc: 'Locate clinics and specialists near you',
  ),
];

class _Counts {
  const _Counts(this.doctors, this.pharmacies, this.hospitals);
  final int doctors;
  final int pharmacies;
  final List<String> hospitals;
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final AnimationController _list = AnimationController(
    vsync: this,
    // 4 staggered items at 60ms apart, each 300ms long.
    duration: const Duration(milliseconds: 480),
  );

  late final Future<_Counts> _counts = _loadCounts();

  @override
  void initState() {
    super.initState();
    _intro.forward().then((_) {
      if (mounted) _list.forward();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _list.dispose();
    super.dispose();
  }

  /// The RN screen `require()`d the seed JSON synchronously at module load.
  /// Flutter assets are async, so the counts resolve through a FutureBuilder
  /// and the strip simply renders empty until they land.
  Future<_Counts> _loadCounts() async {
    try {
      final doctorsRaw = await rootBundle.loadString('assets/seed/doctors.json');
      final pharmaciesRaw = await rootBundle.loadString(
        'assets/seed/pharmacies.json',
      );

      final doctors = (jsonDecode(doctorsRaw) as List)
          .cast<Map<String, dynamic>>();
      final pharmacies = jsonDecode(pharmaciesRaw) as List;

      final hospitals = _featuredHospitals
          .where((h) => doctors.any((d) => d['hospital'] == h))
          .toList();

      return _Counts(doctors.length, pharmacies.length, hospitals);
    } on Object {
      return const _Counts(0, 0, []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(fade);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: fade,
                  child: SlideTransition(
                    position: slide,
                    child: _hero(),
                  ),
                ),
                const SizedBox(height: 32),
                _featureList(),
                const SizedBox(height: 28),
                FutureBuilder<_Counts>(
                  future: _counts,
                  builder: (context, snap) {
                    final counts = snap.data;
                    return FadeTransition(
                      opacity: fade,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (counts != null) _trustStrip(counts),
                          if (counts != null && counts.hospitals.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                'Network includes '
                                '${counts.hospitals.join(", ")} and more nationwide',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.inkFaint,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                FadeTransition(
                  opacity: fade,
                  child: SlideTransition(position: slide, child: _cta(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const VitalsRule(),
      const SizedBox(height: 24),
      const Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'Afya'),
            TextSpan(text: 'Smart', style: TextStyle(color: AppColors.accent)),
          ],
        ),
        style: TextStyle(
          color: AppColors.ink,
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      const SizedBox(height: 10),
      const Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'Find out what your symptoms mean in '),
            TextSpan(
              text: '60 seconds',
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        style: TextStyle(
          color: AppColors.inkMuted,
          fontSize: 16,
          height: 1.5,
        ),
      ),
    ],
  );

  Widget _featureList() => Container(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.rule)),
    ),
    child: Column(
      children: [
        for (var i = 0; i < _features.length; i++)
          _staggered(i, _featureRow(_features[i])),
      ],
    ),
  );

  /// Reproduces Animated.stagger: each row fades and rises 60ms after the
  /// one before it.
  Widget _staggered(int index, Widget child) {
    final start = (index * 60) / 480;
    final anim = CurvedAnimation(
      parent: _list,
      curve: Interval(start, (start + 300 / 480).clamp(0.0, 1.0)),
    );

    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }

  Widget _featureRow(({IconData icon, String title, String desc}) f) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.rule)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Structure comes from thin rule lines, not cards.
              Container(width: 2, color: AppColors.ruleStrong),
              const SizedBox(width: 12),
              Icon(f.icon, size: 18, color: AppColors.ink),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.title,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      f.desc,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _trustStrip(_Counts counts) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 6,
    runSpacing: 4,
    children: [
      const Icon(
        Icons.verified_user_outlined,
        size: 14,
        color: AppColors.inkFaint,
      ),
      _trustNumber('${counts.doctors}+ doctors'),
      const Text('·', style: TextStyle(color: AppColors.ruleStrong)),
      _trustNumber('${counts.pharmacies}+ pharmacies'),
      const Text('·', style: TextStyle(color: AppColors.ruleStrong)),
      const Text(
        'Private and secure',
        style: TextStyle(color: AppColors.inkFaint, fontSize: 12),
      ),
    ],
  );

  Widget _trustNumber(String text) => Text(
    text,
    style: const TextStyle(
      color: AppColors.ink,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  );

  Widget _cta(BuildContext context) => Column(
    children: [
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => context.push(Routes.healthCheck),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.ink,
            foregroundColor: AppColors.paper,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: const StadiumBorder(),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Start your check-in',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 18),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Not a replacement for professional medical advice',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.inkFaint, fontSize: 11),
      ),
    ],
  );
}
