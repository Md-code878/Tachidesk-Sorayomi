// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/manga_book/manga_book_repository.dart';
import '../../../domain/chapter/chapter_model.dart';
import 'dart:convert';
import '../../../data/offline_cache/offline_cache_manager.dart';
import '../../../../../global_providers/global_providers.dart';
import '../../../domain/chapter_page/chapter_page_model.dart';

part 'reader_controller.g.dart';

@riverpod
FutureOr<ChapterDto?> chapter(
  Ref ref, {
  required int chapterId,
}) =>
    ref.watch(mangaBookRepositoryProvider).getChapter(chapterId: chapterId);

@riverpod
Future<ChapterPagesDto?> chapterPages(Ref ref, {required int chapterId}) async {
  final offlineCacheManager = ref.read(offlineCacheManagerProvider);
  if (offlineCacheManager.isChapterCachedSync(chapterId)) {
    final prefs = ref.read(sharedPreferencesProvider);
    final jsonStr = prefs.getString('offline_chapter_pages_$chapterId');
    if (jsonStr != null) {
      try {
        final jsonMap = jsonDecode(jsonStr);
        return ChapterPagesDto.fromJson(jsonMap);
      } catch (e) {
        // Fallback to network request
      }
    }
  }

  return ref
      .watch(mangaBookRepositoryProvider)
      .getChapterPages(chapterId: chapterId);
}
