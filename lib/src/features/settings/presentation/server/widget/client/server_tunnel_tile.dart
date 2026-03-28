import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../widgets/input_popup/settings_prop_tile.dart';

part 'server_tunnel_tile.g.dart';

@riverpod
class ServerTunnelToggle extends _$ServerTunnelToggle
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(
        DBKeys.serverTunnelToggle,
        initial: kIsWeb ? false : DBKeys.serverTunnelToggle.initial,
      );
}

class ServerTunnelTile extends ConsumerWidget {
  const ServerTunnelTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tunnelToggle = ref.watch(serverTunnelToggleProvider).ifNull();
    return SettingsPropTile(
      title: 'Use Tunnel URL',
      subtitle: tunnelToggle ? 'Connect via Tunnel URL instead of Localhost' : null,
      leading: const Icon(Icons.cloud_sync_rounded),
      trailing: Switch(
        value: tunnelToggle,
        onChanged: ref.read(serverTunnelToggleProvider.notifier).update,
      ),
      type: SettingsPropType<void>.switchToggle(),
    );
  }
}
