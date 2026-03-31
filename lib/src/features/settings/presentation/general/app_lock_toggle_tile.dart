import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../security/presentation/app_lock_screen.dart';

class AppLockToggleTile extends ConsumerWidget {
  const AppLockToggleTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Platform.isAndroid) return const SizedBox.shrink();

    final isLocked = ref.watch(appLockToggleProvider) ?? false;
    return SwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: const Icon(Icons.fingerprint_rounded),
      title: const Text('App Lock (Fingerprint/Biometric)'),
      value: isLocked,
      onChanged: ref.read(appLockToggleProvider.notifier).update,
    );
  }
}
