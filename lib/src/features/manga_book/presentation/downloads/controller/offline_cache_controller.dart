import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/offline_cache/offline_cache_manager.dart';

part 'offline_cache_controller.g.dart';

enum OfflineCacheState {
  none,
  downloading,
  cached,
  error,
}

@riverpod
class OfflineCacheController extends _$OfflineCacheController {
  @override
  OfflineCacheState build(int chapterId) {
    final cacheManager = ref.read(offlineCacheManagerProvider);
    if (cacheManager.isChapterCachedSync(chapterId)) {
      return OfflineCacheState.cached;
    }
    return OfflineCacheState.none;
  }

  Future<void> cacheChapter() async {
    if (state == OfflineCacheState.downloading ||
        state == OfflineCacheState.cached) {
      return;
    }

    state = OfflineCacheState.downloading;
    try {
      final cacheManager = ref.read(offlineCacheManagerProvider);
      await cacheManager.cacheChapterPages(chapterId);

      if (cacheManager.isChapterCachedSync(chapterId)) {
        state = OfflineCacheState.cached;
      } else {
        state = OfflineCacheState.error;
      }
    } catch (e) {
      state = OfflineCacheState.error;
    }
  }
}
