// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../services/downloader/database.dart';
import '../../../../../utils/logger/logger.dart';
import '../../../data/manga_book/manga_book_repository.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/chapter_page/chapter_page_model.dart';
import '../../../domain/chapter_page/graphql/__generated__/fragment.graphql.dart';

part 'reader_controller.g.dart';

@riverpod
FutureOr<ChapterDto?> chapter(
  Ref ref, {
  required int chapterId,
}) =>
    ref.watch(mangaBookRepositoryProvider).getChapter(chapterId: chapterId);

@riverpod
Future<ChapterPagesDto?> chapterPages(Ref ref, {required int chapterId}) async {
  // Check if chapter is downloaded locally
  final dbChapter = await DownloadDatabase.instance.getChapter(chapterId);

  if (dbChapter != null && dbChapter['downloadStatus'] == 1) {
    final appDir = await getApplicationDocumentsDirectory();
    final localPathDb = dbChapter['local_path'] as String?;

    // Fallback logic for legacy `downloads` path if local_path is null (for backward compatibility if needed)
    final mangaId = dbChapter['mangaId'] as int;
    final localPath = localPathDb != null ? '${appDir.path}/$localPathDb' : '${appDir.path}/downloads/$mangaId/$chapterId';

    logger.i('Loading chapter $chapterId from local storage path: $localPath');

    final dir = Directory(localPath);
    if (await dir.exists()) {
      final List<String> localFilePaths = [];

      // Load actual files from directory to get correct extensions
      final files = dir.listSync().whereType<File>().toList();

      // Sort files by name (0.jpg, 1.jpg, 2.jpg)
      files.sort((a, b) {
        final aName = a.path.split('/').last.split('.').first;
        final bName = b.path.split('/').last.split('.').first;
        final aNum = int.tryParse(aName) ?? 0;
        final bNum = int.tryParse(bName) ?? 0;
        return aNum.compareTo(bNum);
      });

      for (var file in files) {
        if (file.existsSync()) {
          // prepend file:// scheme so ServerImage handles it as an absolute URL and correctly parses the extension
          localFilePaths.add('file://${file.path}');
        } else {
          logger.e('Missing local file: ${file.path}');
        }
      }

      return Fragment$ChapterPagesDto(
        chapter: Fragment$ChapterPagesDto$chapter(
          id: chapterId,
          pageCount: files.length, // use actual found files
        ),
        pages: localFilePaths,
      );
    } else {
      logger.e('Expected local directory does not exist: $localPath');
    }
  }

  // Fallback to server
  return ref.watch(mangaBookRepositoryProvider).getChapterPages(chapterId: chapterId);
}
