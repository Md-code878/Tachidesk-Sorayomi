import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../widgets/input_popup/settings_prop_tile.dart';
import 'server_tunnel_tile.dart';

part 'server_tunnel_url_tile.g.dart';

@riverpod
class ServerTunnelUrl extends _$ServerTunnelUrl
    with SharedPreferenceClientMixin<String> {
  @override
  String? build() => initialize(
        DBKeys.serverTunnelUrl,
        initial: DBKeys.serverTunnelUrl.initial,
      );
}

class ServerTunnelUrlTile extends ConsumerWidget {
  const ServerTunnelUrlTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tunnelToggle = ref.watch(serverTunnelToggleProvider).ifNull();
    final tunnelUrl = ref.watch(serverTunnelUrlProvider);

    return SettingsPropTile(
      title: 'Tunnel URL',
      subtitle: tunnelToggle ? tunnelUrl : null,
      leading: const Icon(Icons.hub_rounded),
      type: SettingsPropType<void>.textField(
        hintText: 'Enter Tunnel URL',
        value: tunnelUrl,
        onChanged: tunnelToggle
            ? (value) async {
                final tempUrl = value.endsWith('/')
                    ? value.substring(0, value.length - 1)
                    : value;
                ref.read(serverTunnelUrlProvider.notifier).update(tempUrl);
                return;
              }
            : null,
      ),
    );
  }
}
