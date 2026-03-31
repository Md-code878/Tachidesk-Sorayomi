import 'dart:convert';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../constants/endpoints.dart';
import '../../../../constants/enum.dart';
import '../../../../global_providers/global_providers.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../../settings/presentation/server/widget/client/server_tunnel_tile.dart';
import '../../../settings/presentation/server/widget/client/server_tunnel_url_tile.dart';
import '../../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../manga_book/manga_book_repository.dart';

part 'offline_cache_manager.g.dart';

class OfflineCacheManager {
  OfflineCacheManager(this.ref);

  final OfflineCacheManagerRef ref;

  String _buildUrl(String url) {
    return "${Endpoints.baseApi(
      baseUrl: ref.read(serverUrlProvider),
      port: ref.read(serverPortProvider),
      addPort: ref.read(serverPortToggleProvider).ifNull(),
      isTunnel: ref.read(serverTunnelToggleProvider).ifNull(),
      tunnelUrl: ref.read(serverTunnelUrlProvider),
      appendApiToUrl: false,
    )}"
        "$url";
  }

  Map<String, String>? _buildHeaders() {
    final authType = ref.read(authTypeKeyProvider);
    final basicToken = ref.read(credentialsProvider);
    if (authType == AuthType.basic && basicToken != null) {
      return {"Authorization": basicToken};
    }
    return null;
  }

  Future<void> cacheChapterPages(int chapterId) async {
    final repo = ref.read(mangaBookRepositoryProvider);
    final chapterPages = await repo.getChapterPages(chapterId: chapterId);

    if (chapterPages == null || chapterPages.pages.isEmpty) {
      return;
    }

    final cacheManager = DefaultCacheManager();
    final headers = _buildHeaders();

    // Cache the DTO itself in SharedPreferences so we can read it offline without GraphQL
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(
        'offline_chapter_pages_$chapterId', jsonEncode(chapterPages.toJson()));

    for (final url in chapterPages.pages) {
      final fullUrl = _buildUrl(url);
      try {
        // We only use DefaultCacheManager but force it to download.
        // It relies on Cache-Control headers if we don't use a custom manager.
        // For simplicity we use the default manager, which will satisfy standard offline reads.
        await cacheManager.downloadFile(fullUrl, authHeaders: headers);
      } catch (e) {
        // Handle error per page, or skip
      }
    }

    // Mark as cached in prefs
    await prefs.setBool('offline_cached_$chapterId', true);
  }

  bool isChapterCachedSync(int chapterId) {
    final prefs = ref.read(sharedPreferencesProvider);
    return prefs.getBool('offline_cached_$chapterId') ?? false;
  }
}

@riverpod
OfflineCacheManager offlineCacheManager(OfflineCacheManagerRef ref) {
  return OfflineCacheManager(ref);
}
