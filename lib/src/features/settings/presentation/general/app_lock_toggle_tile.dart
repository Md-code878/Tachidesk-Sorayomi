import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../security/presentation/app_lock_screen.dart';

class AppLockToggleTile extends ConsumerWidget {
  const AppLockToggleTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Platform.isAndroid) return const SizedBox.shrink();

    final isLocked = ref.watch(appLockToggleProvider) ?? false;
    return SettingsPropTile(
      title: 'App Lock (Fingerprint/Biometric)',
      leading: const Icon(Icons.fingerprint_rounded),
      trailing: Switch(
        value: isLocked,
        onChanged: ref.read(appLockToggleProvider.notifier).update,
      ),
      type: const SettingsPropType<void>.switchTile(),
    );
  }
}
