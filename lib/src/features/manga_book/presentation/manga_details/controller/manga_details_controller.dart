// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../library/domain/category/category_model.dart';
import '../../../data/manga_book/manga_book_repository.dart';
import '../../../../../services/downloader/database.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/chapter/graphql/__generated__/fragment.graphql.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../domain/manga/manga_model.dart';
import '../../../domain/manga/graphql/__generated__/fragment.graphql.dart';

part 'manga_details_controller.g.dart';

@riverpod
class MangaWithId extends _$MangaWithId {
  @override
  Future<MangaDto?> build({required int mangaId}) async {
    final result = await AsyncValue.guard(
        () => ref.watch(mangaBookRepositoryProvider).getManga(mangaId: mangaId));

    // If offline or error, we keep previous state if it exists
    if (result.hasError) {
      if (state.hasValue && state.value != null) {
        return state.value;
      }
      // If we don't have previous state but offline, check if we have it in DB to prevent crash
      final localChapters = await DownloadDatabase.instance.getChaptersForManga(mangaId);
      if (localChapters.isNotEmpty) {
        final mangaTitle = localChapters.first['mangaTitle'] as String? ?? 'Unknown Manga';
        return Fragment$MangaDto(
          id: mangaId,
          title: mangaTitle,
          url: '',
          artist: null,
          author: null,
          description: 'Offline Manga',
          genre: [],
          status: Enum$MangaStatus.$unknown,
          thumbnailUrl: null,
          updateStrategy: Enum$UpdateStrategy.$unknown,
          initialized: true,
          inLibrary: true,
          meta: [],
          realUrl: null,
          downloadCount: localChapters.length,
          inLibraryAt: '',
          sourceId: '0',
          unreadCount: 0,
        );
      }
    }

    return result.value;
  }

  Future<void> refresh() async {
    final result = await AsyncValue.guard(
        () => ref.read(mangaBookRepositoryProvider).getManga(mangaId: mangaId));
    if (result.hasError) {
      state = result.copyWithPrevious(state);
    } else {
      state = result;
    }
  }
}

@riverpod
class MangaChapterList extends _$MangaChapterList {
  @override
  Future<List<ChapterDto>?> build({required int mangaId}) async {
    final result = await AsyncValue.guard(
        () => ref.watch(mangaBookRepositoryProvider).getChapterList(mangaId));
    ref.keepAlive();

    final localDbChapters = await DownloadDatabase.instance.getChaptersForManga(mangaId);

    if (result.hasError) {
      if (state.hasValue && state.value != null) {
         return state.value;
      }

      // Acid Test: If offline, fetch local chapters
      if (localDbChapters.isNotEmpty) {
        return localDbChapters.map((dbChap) {
          return Fragment$ChapterDto(
            id: dbChap['chapterId'] as int,
            mangaId: mangaId,
            name: dbChap['chapterTitle'] as String,
            chapterNumber: 0.0,
            fetchedAt: '0',
            isBookmarked: false,
            isDownloaded: true, // Force downloaded true
            isRead: false,
            lastPageRead: 0,
            lastReadAt: '0',
            pageCount: dbChap['pageCount'] as int,
            sourceOrder: 0,
            uploadDate: '0',
            url: '',
            meta: [],
          );
        }).toList();
      }
      return null;
    }

    // Merge logic: If online, flag local chapters as downloaded
    final serverChapters = result.value;
    if (serverChapters != null && localDbChapters.isNotEmpty) {
      final downloadedIds = localDbChapters
          .where((chap) => chap['downloadStatus'] == 1)
          .map((chap) => chap['chapterId'] as int)
          .toSet();

      return serverChapters.map((chapter) {
        if (downloadedIds.contains(chapter.id)) {
          return chapter.copyWith(isDownloaded: true);
        }
        return chapter;
      }).toList();
    }

    return serverChapters;
  }

  Future<void> refresh([bool onlineFetch = false]) async {
    final result = await AsyncValue.guard(
        () => ref.read(mangaBookRepositoryProvider).getChapterList(mangaId));
    ref.keepAlive();
    if (result.hasError) {
      state = result.copyWithPrevious(state);
    } else {
      // Merge logic on refresh
      final localDbChapters = await DownloadDatabase.instance.getChaptersForManga(mangaId);
      final serverChapters = result.value;
      if (serverChapters != null && localDbChapters.isNotEmpty) {
        final downloadedIds = localDbChapters
            .where((chap) => chap['downloadStatus'] == 1)
            .map((chap) => chap['chapterId'] as int)
            .toSet();

        state = AsyncData(serverChapters.map((chapter) {
          if (downloadedIds.contains(chapter.id)) {
            return chapter.copyWith(isDownloaded: true);
          }
          return chapter;
        }).toList());
      } else {
        state = result;
      }
    }
  }

  void updateChapter(int index, ChapterDto chapter) {
    try {
      final newList = [...?state.valueOrNull];
      newList[index] = chapter;
      state = AsyncData<List<ChapterDto>?>(newList).copyWithPrevious(state);
    } catch (e) {
      //
    }
  }
}

@riverpod
Set<String> mangaScanlatorList(Ref ref, {required int mangaId}) {
  final chapterList = ref.watch(mangaChapterListProvider(mangaId: mangaId));
  final scanlatorList = <String>{};
  chapterList.whenData((data) {
    if (data == null) return;
    for (final chapter in data) {
      if (chapter.scanlator.isNotBlank) {
        scanlatorList.add(chapter.scanlator!);
      }
    }
  });
  return scanlatorList;
}

@riverpod
class MangaChapterFilterScanlator extends _$MangaChapterFilterScanlator {
  @override
  String build({required int mangaId}) {
    final manga = ref.watch(mangaWithIdProvider(mangaId: mangaId));
    return manga.valueOrNull?.metaData.scanlator ?? MangaMetaKeys.scanlator.key;
  }

  void update(String? scanlator) async {
    await AsyncValue.guard(
      () => ref.read(mangaBookRepositoryProvider).patchMangaMeta(
            mangaId: mangaId,
            key: MangaMetaKeys.scanlator.key,
            value: scanlator ?? MangaMetaKeys.scanlator.key,
          ),
    );
    ref.invalidate(mangaWithIdProvider(mangaId: mangaId));
    state = scanlator ?? MangaMetaKeys.scanlator.key;
  }
}

@riverpod
AsyncValue<List<ChapterDto>?> mangaChapterListWithFilter(
  Ref ref, {
  required int mangaId,
}) {
  final chapterList = ref.watch(mangaChapterListProvider(mangaId: mangaId));
  final chapterFilterUnread = ref.watch(mangaChapterFilterUnreadProvider);
  final chapterFilterDownloaded =
      ref.watch(mangaChapterFilterDownloadedProvider);
  final chapterFilterBookmark = ref.watch(mangaChapterFilterBookmarkedProvider);
  final ChapterSort sortedBy = ref.watch(mangaChapterSortProvider) ??
      DBKeys.chapterSortDirection.initial;
  final sortedDirection =
      ref.watch(mangaChapterSortDirectionProvider).ifNull(true);

  final chapterFilterScanlator =
      ref.watch(mangaChapterFilterScanlatorProvider(mangaId: mangaId));

  bool applyChapterFilter(ChapterDto chapter) {
    if (chapterFilterUnread != null &&
        (chapterFilterUnread ^ !(chapter.isRead.ifNull()))) {
      return false;
    }

    if (chapterFilterDownloaded != null &&
        (chapterFilterDownloaded ^ (chapter.isDownloaded.ifNull()))) {
      return false;
    }

    if (chapterFilterBookmark != null &&
        (chapterFilterBookmark ^ (chapter.isBookmarked.ifNull()))) {
      return false;
    }

    if (chapterFilterScanlator != MangaMetaKeys.scanlator.key &&
        chapter.scanlator != chapterFilterScanlator) {
      return false;
    }
    return true;
  }

  int applyChapterSort(ChapterDto m1, ChapterDto m2) {
    final sortDirToggle = (sortedDirection ? 1 : -1);
    return (switch (sortedBy) {
          ChapterSort.fetchedDate => (int.tryParse(m1.fetchedAt) ?? 0)
              .compareTo(int.tryParse(m2.fetchedAt) ?? 0),
          ChapterSort.source => (m1.index).compareTo(m2.index),
          ChapterSort.uploadDate => (int.tryParse(m1.uploadDate) ?? 0)
              .compareTo(int.tryParse(m2.uploadDate) ?? 0),
        }) *
        sortDirToggle;
  }

  return chapterList.copyWithData(
    (data) => [...?data?.where(applyChapterFilter)]..sort(applyChapterSort),
  );
}

@riverpod
ChapterDto? firstUnreadInFilteredChapterList(
  Ref ref, {
  required int mangaId,
}) {
  final isAscSorted = ref.watch(mangaChapterSortDirectionProvider) ??
      DBKeys.chapterSortDirection.initial;
  final filteredList = ref
      .watch(mangaChapterListWithFilterProvider(mangaId: mangaId))
      .valueOrNull;
  if (filteredList == null) {
    return null;
  } else {
    if (isAscSorted) {
      return filteredList
          .firstWhereOrNull((element) => !element.isRead.ifNull(true));
    } else {
      return filteredList
          .lastWhereOrNull((element) => !element.isRead.ifNull(true));
    }
  }
}

@riverpod
({ChapterDto? first, ChapterDto? second})? getNextAndPreviousChapters(
  Ref ref, {
  required int mangaId,
  required int chapterId,
  bool shouldAscSort = true,
}) {
  final isAscSorted = ref.watch(mangaChapterSortDirectionProvider) ??
      DBKeys.chapterSortDirection.initial;
  final filteredList = ref
      .watch(mangaChapterListWithFilterProvider(mangaId: mangaId))
      .valueOrNull;
  if (filteredList == null) {
    return null;
  } else {
    final current =
        filteredList.indexWhere((element) => element.id == chapterId);
    final prevChapter = current > 0 ? filteredList[current - 1] : null;
    final nextChapter =
        current < (filteredList.length - 1) ? filteredList[current + 1] : null;
    return (
      first: shouldAscSort && isAscSorted ? nextChapter : prevChapter,
      second: shouldAscSort && isAscSorted ? prevChapter : nextChapter,
    );
  }
}

@riverpod
class MangaChapterSort extends _$MangaChapterSort
    with SharedPreferenceEnumClientMixin<ChapterSort> {
  @override
  ChapterSort? build() => initialize(
        DBKeys.chapterSort,
        enumList: ChapterSort.values,
      );
}

@riverpod
class MangaChapterSortDirection extends _$MangaChapterSortDirection
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.chapterSortDirection);
}

@riverpod
class MangaChapterFilterDownloaded extends _$MangaChapterFilterDownloaded
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.chapterFilterDownloaded);
}

@riverpod
class MangaChapterFilterUnread extends _$MangaChapterFilterUnread
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.chapterFilterUnread);
}

@riverpod
class MangaChapterFilterBookmarked extends _$MangaChapterFilterBookmarked
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.chapterFilterBookmarked);
}

@riverpod
class MangaCategoryList extends _$MangaCategoryList {
  @override
  FutureOr<Map<String, CategoryDto>?> build(int mangaId) async {
    final result = await ref
        .watch(mangaBookRepositoryProvider)
        .getMangaCategoryList(mangaId: mangaId);
    return {
      for (CategoryDto i in (result ?? <CategoryDto>[])) "${i.id}": i,
    };
  }

  Future<void> refresh() async {
    final result = await AsyncValue.guard(() => ref
        .read(mangaBookRepositoryProvider)
        .getMangaCategoryList(mangaId: mangaId));
    state = result.copyWithData((data) => {
          for (CategoryDto i in (data ?? <CategoryDto>[])) "${i.id}": i,
        });
  }
}
