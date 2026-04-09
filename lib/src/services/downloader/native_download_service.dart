import 'dart:async';
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
  final Dio _dio = Dio(BaseOptions(
    headers: {'Cache-Control': 'no-cache'}, // Disable caching to force raw fetch
  ));

  @override
  Map<int, double> build() {
    return {};
  }

  void _verifyFileSize(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('ROM write failed: File does not exist at $filePath');
    }
    final size = file.statSync().size;
    logger.i('Stat($filePath).size = $size');
    if (size == 0) {
      throw Exception('ROM write failed: File size is 0 bytes for $filePath');
    }
  }

  Future<void> downloadChapter(
    int mangaId,
    ChapterDto chapter,
  ) async {
    final chapterId = chapter.id;
    state = {...state, chapterId: 0.0};

    try {
      final relativePath = 'native_downloads/$mangaId/$chapterId';

      await DownloadDatabase.instance.insertChapter({
        'mangaId': mangaId,
        'chapterId': chapterId,
        'chapterTitle': chapter.name,
        'downloadStatus': 0, // 0 = downloading
        'pageCount': 0,
        'local_path': relativePath,
      });

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

      final appDir = await getApplicationDocumentsDirectory();
      final chapterDir = Directory('${appDir.path}/$relativePath');

      // Explicitly force creation of the directory for ROM persistence
      if (!await chapterDir.exists()) {
        await chapterDir.create(recursive: true);
      }

      final authType = ref.read(authTypeKeyProvider);
      final basicToken = ref.read(credentialsProvider);

      if (authType == AuthType.basic && basicToken != null) {
        _dio.options.headers["Authorization"] = basicToken;
      }

      int downloadedPages = 0;

      // Parallelize downloads in batches of 5 to optimize speed without overwhelming server
      final int batchSize = 5;
      for (int i = 0; i < pages.length; i += batchSize) {
        final end = (i + batchSize < pages.length) ? i + batchSize : pages.length;
        final batch = pages.sublist(i, end);

        final futures = batch.asMap().entries.map((entry) async {
          final globalIndex = i + entry.key;
          final url = entry.value;
          final uri = Uri.parse(url);
          final ext = uri.pathSegments.isNotEmpty ? uri.pathSegments.last.split('.').last : 'jpg';
          final validExt = ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext.toLowerCase()) ? ext : 'jpg';

          final filePath = '${chapterDir.path}/$globalIndex.$validExt';

          // ROM Check: if already exists and size > 0, skip
          final existingFile = File(filePath);
          if (existingFile.existsSync() && existingFile.statSync().size > 0) {
            return;
          }

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

          // Direct I/O via Dio.download
          await _dio.download(fullUrl, filePath);

          // Verify ROM Write
          _verifyFileSize(filePath);
        });

        await Future.wait(futures);

        downloadedPages += batch.length;
        state = {...state, chapterId: downloadedPages / pages.length};
      }

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
    final chapterDir = Directory('${appDir.path}/native_downloads/$mangaId/$chapterId');
    if (await chapterDir.exists()) {
      await chapterDir.delete(recursive: true);
    }
    await DownloadDatabase.instance.deleteChapter(chapterId);
  }
}
