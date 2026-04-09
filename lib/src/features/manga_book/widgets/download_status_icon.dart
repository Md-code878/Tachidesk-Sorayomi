// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/app_sizes.dart';
import '../../../services/downloader/database.dart';
import '../../../services/downloader/native_download_service.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/misc/toast/toast.dart';
import '../../../widgets/custom_circular_progress_indicator.dart';
import '../data/downloads/downloads_repository.dart';
import '../data/manga_book/manga_book_repository.dart';
import '../domain/chapter/chapter_model.dart';
import '../domain/downloads/downloads_model.dart';
import '../presentation/downloads/controller/downloads_controller.dart';

class DownloadStatusIcon extends HookConsumerWidget {
  const DownloadStatusIcon({
    super.key,
    required this.updateData,
    required this.chapter,
    required this.mangaId,
    required this.isDownloaded,
  });
  final AsyncCallback updateData;
  final ChapterDto chapter;
  final int mangaId;
  final bool isDownloaded;

  Future<void> newUpdatePair(
      WidgetRef ref, ValueSetter<bool> setIsLoading) async {
    try {
      setIsLoading(true);
      await updateData();
      setIsLoading(false);
    } catch (e) {
      // Ignore
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = useState(false);
    final toast = ref.watch(toastProvider);

    // Watch native downloader state
    final nativeDownloads = ref.watch(nativeDownloadServiceProvider);
    final nativeProgress = nativeDownloads[chapter.id];

    // Check local database status
    final localStatus = useState<int?>(null);

    Future<void> checkLocalStatus() async {
      final dbChapter = await DownloadDatabase.instance.getChapter(chapter.id);
      if (dbChapter != null) {
        localStatus.value = dbChapter['downloadStatus'] as int;
      } else {
        localStatus.value = null;
      }
    }

    useEffect(() {
      checkLocalStatus();
      return null;
    }, [nativeProgress]);

    // Combined download state
    final isDownloading = nativeProgress != null || localStatus.value == 0;
    final isNativeDownloaded = localStatus.value == 1;
    final isError = localStatus.value == -1;

    // We still watch the server download update in case of background updates, but native takes precedence
    final downloadUpdate = ref.watch(downloadsFromIdProvider(chapter.id));

    useEffect(() {
      if (downloadUpdate?.state == DownloadState.FINISHED || localStatus.value == 1) {
        Future.microtask(
            () => newUpdatePair(ref, (value) => isLoading.value = value));
      }
      return;
    }, [downloadUpdate?.state, localStatus.value]);

    if (isLoading.value) {
      return Padding(
        padding: KEdgeInsets.h8.size,
        child: MiniCircularProgressIndicator(color: context.iconColor),
      );
    } else {
      if (isError) {
        return IconButton(
          onPressed: () {
            ref.read(nativeDownloadServiceProvider.notifier).downloadChapter(mangaId, chapter);
          },
          icon: const Icon(Icons.replay_rounded),
        );
      } else if (isDownloading) {
        return IconButton(
          onPressed: () {
            // Can't easily cancel yet, but we could add that functionality.
            // For now, do nothing.
          },
          icon: MiniCircularProgressIndicator(
            value: nativeProgress == 0.0 ? null : nativeProgress,
            color: context.iconColor,
          ),
        );
      } else if (downloadUpdate != null) {
        // Fallback to server queue view if we are downloading remotely
        if (downloadUpdate.state == DownloadState.ERROR) {
          return IconButton(
            onPressed: () async {
              try {
                (await AsyncValue.guard(() async {
                  final repo = ref.read(downloadsRepositoryProvider);
                  await repo.removeChapterFromDownloadQueue(chapter.id);
                  await repo.addChaptersBatchToDownloadQueue([chapter.id]);
                })).showToastOnError(toast);
              } catch (e) {
                // Ignore
              }
            },
            icon: const Icon(Icons.replay_rounded),
          );
        } else {
          return IconButton(
            onPressed: () async {
              try {
                (await AsyncValue.guard(() async {
                  final repo = ref.read(downloadsRepositoryProvider);
                  await repo.removeChapterFromDownloadQueue(chapter.id);
                })).showToastOnError(toast);
              } catch (e) {
                // Ignore
              }
            },
            icon: MiniCircularProgressIndicator(
              value: downloadUpdate.progress == 0 ? null : downloadUpdate.progress,
              color: context.iconColor,
            ),
          );
        }
      } else {
        if (isDownloaded || isNativeDownloaded) {
          return IconButton(
            icon: const Icon(Icons.check_circle_rounded),
            onPressed: () async {
              if (isNativeDownloaded) {
                await ref.read(nativeDownloadServiceProvider.notifier).deleteChapter(mangaId, chapter.id);
                localStatus.value = null;
              } else {
                (await AsyncValue.guard(
                  () => ref
                      .read(mangaBookRepositoryProvider)
                      .deleteChapters([chapter.id]),
                )).showToastOnError(toast);
              }
              await newUpdatePair(ref, (value) => isLoading.value = value);
            },
          );
        } else {
          return IconButton(
            icon: const Icon(Icons.download_for_offline_rounded),
            onPressed: () {
              // Initiate Native Download
              ref.read(nativeDownloadServiceProvider.notifier).downloadChapter(mangaId, chapter);
              checkLocalStatus();
            },
          );
        }
      }
    }
  }
}
