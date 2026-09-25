import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router.dart';
import '../../../core/theme.dart';

/// Shared chrome for the pages reached from the profile menu: the same teal
/// header band as the profile screen, with a back arrow in place of the
/// settings icon.
class ProfileSubpage extends StatelessWidget {
  const ProfileSubpage({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FA),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: AppColors.brand,
          padding: EdgeInsets.fromLTRB(
            8,
            MediaQuery.viewPaddingOf(context).top + 8,
            20,
            16,
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go(Routes.profile),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              const SizedBox(width: 4),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

/// White rounded card matching the profile screen's sections.
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppPalette.hairline),
    ),
    child: child,
  );
}

/// Full-width primary button with an inline spinner while [busy].
class ProfilePrimaryButton extends StatelessWidget {
  const ProfilePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy ? null : onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.brand,
      minimumSize: const Size.fromHeight(50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    child: busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Text(label),
  );
}
