import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../constants/endpoints.dart';
import '../../constants/enum.dart';
import '../../features/manga_book/data/manga_book/manga_book_repository.dart';
import '../../features/manga_book/domain/chapter/chapter_model.dart';
import '../../features/settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../features/settings/presentation/server/widget/client/server_tunnel_tile.dart';
import '../../features/settings/presentation/server/widget/client/server_tunnel_url_tile.dart';
import '../../features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../../global_providers/global_providers.dart';
import '../../utils/extensions/custom_extensions.dart';
import '../../utils/logger/logger.dart';
import 'database.dart';

part 'native_download_service.g.dart';

@riverpod
class NativeDownloadService extends _$NativeDownloadService {
  final Dio _dio = Dio();

  @override
  Map<int, double> build() {
    return {};
  }

  Future<void> downloadChapter(
    int mangaId,
    ChapterDto chapter,
  ) async {
    final chapterId = chapter.id;
    // Set initial progress
    state = {...state, chapterId: 0.0};

    try {
      // 1. Mark as queued in DB
      await DownloadDatabase.instance.insertChapter({
        'mangaId': mangaId,
        'chapterId': chapterId,
        'chapterTitle': chapter.name,
        'downloadStatus': 0, // 0 = downloading
        'pageCount': 0,
      });

      // 2. Fetch pages
      final repo = ref.read(mangaBookRepositoryProvider);
      final chapterPages = await repo.getChapterPages(chapterId: chapterId);

      if (chapterPages == null || chapterPages.pages.isEmpty) {
        throw Exception('No pages found for chapter');
      }

      final pages = chapterPages.pages;
      await DownloadDatabase.instance.updateChapterStatus(chapterId, 0);

      final db = await DownloadDatabase.instance.database;
      await db.update(
        'downloaded_chapters',
        {'pageCount': pages.length},
        where: 'chapterId = ?',
        whereArgs: [chapterId],
      );

      // 3. Prepare directory
      final appDir = await getApplicationDocumentsDirectory();
      final chapterDir = Directory('${appDir.path}/downloads/$mangaId/$chapterId');
      if (!await chapterDir.exists()) {
        await chapterDir.create(recursive: true);
      }

      // 4. Determine Auth
      final authType = ref.read(authTypeKeyProvider);
      final basicToken = ref.read(credentialsProvider);

      if (authType == AuthType.basic && basicToken != null) {
        _dio.options.headers["Authorization"] = basicToken;
      }

      // 5. Download pages
      int downloadedPages = 0;
      for (int i = 0; i < pages.length; i++) {
        final url = pages[i];
        final uri = Uri.parse(url);
        final ext = uri.pathSegments.isNotEmpty ? uri.pathSegments.last.split('.').last : 'jpg';
        final validExt = ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext.toLowerCase()) ? ext : 'jpg';

        final filePath = '${chapterDir.path}/$i.$validExt';

        String fullUrl = url;
        if (!url.startsWith('http')) {
          final baseApi = Endpoints.baseApi(
            baseUrl: ref.read(serverUrlProvider),
            port: ref.read(serverPortProvider),
            addPort: ref.read(serverPortToggleProvider).ifNull(),
            isTunnel: ref.read(serverTunnelToggleProvider).ifNull(),
            tunnelUrl: ref.read(serverTunnelUrlProvider),
            appendApiToUrl: false,
          );
          fullUrl = "$baseApi$url";
        }

        await _dio.download(fullUrl, filePath);

        downloadedPages++;
        state = {...state, chapterId: downloadedPages / pages.length};
      }

      // 6. Mark as complete
      await DownloadDatabase.instance.updateChapterStatus(chapterId, 1); // 1 = downloaded

      final newState = {...state};
      newState.remove(chapterId);
      state = newState;

    } catch (e) {
      logger.w('Download failed for chapter $chapterId: $e');
      await DownloadDatabase.instance.updateChapterStatus(chapterId, -1); // -1 = error

      final newState = {...state};
      newState.remove(chapterId);
      state = newState;
    }
  }

  Future<void> deleteChapter(int mangaId, int chapterId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final chapterDir = Directory('${appDir.path}/downloads/$mangaId/$chapterId');
    if (await chapterDir.exists()) {
      await chapterDir.delete(recursive: true);
    }
    await DownloadDatabase.instance.deleteChapter(chapterId);
  }
}
