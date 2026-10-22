import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/connectivity_controller.dart';

/// Wraps the whole app (via MaterialApp.builder) and pins a strip above every
/// screen while the device is offline. The strip takes the status-bar inset
/// itself, so the screen below is laid out as if it sat under the strip.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Unknown (still loading, or the plugin failed) counts as online: never
    // claim the user is offline without evidence.
    final offline = ref.watch(onlineProvider).value == false;

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: offline
              ? const _Strip()
              : const SizedBox(width: double.infinity),
        ),
        // Always wrapped, so going on/offline never changes the tree shape
        // above the navigator and remounts every screen.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: offline,
            child: child,
          ),
        ),
      ],
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip();

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.danger,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.wifi_off, size: 16, color: AppColors.paper),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'No internet connection',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.paper,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
