import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../widgets/custom_circular_progress_indicator.dart';
import '../presentation/downloads/controller/offline_cache_controller.dart';

class OfflineCacheStatusIcon extends HookConsumerWidget {
  const OfflineCacheStatusIcon({
    super.key,
    required this.chapterId,
  });

  final int chapterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(offlineCacheControllerProvider(chapterId));
    final controller =
        ref.read(offlineCacheControllerProvider(chapterId).notifier);

    if (state == OfflineCacheState.downloading) {
      return IconButton(
        onPressed: null,
        icon: MiniCircularProgressIndicator(
          color: context.iconColor,
        ),
      );
    } else if (state == OfflineCacheState.cached) {
      return IconButton(
        icon: const Icon(Icons.offline_pin_rounded),
        color: context.iconColor,
        onPressed: () {
          // Future: Add logic to clear from cache if requested
        },
      );
    } else if (state == OfflineCacheState.error) {
      return IconButton(
        icon: const Icon(Icons.error_outline_rounded),
        color: Colors.red,
        onPressed: () => controller.cacheChapter(),
      );
    } else {
      // none
      return IconButton(
        icon: const Icon(Icons.offline_pin_outlined),
        onPressed: () => controller.cacheChapter(),
      );
    }
  }
}
