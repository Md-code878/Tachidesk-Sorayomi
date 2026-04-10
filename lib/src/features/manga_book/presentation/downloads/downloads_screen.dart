// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../routes/router_config.dart';
import '../../../../services/downloader/database.dart';
import '../../../../services/downloader/native_download_service.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/emoticons.dart';

class DownloadsScreen extends HookConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch only the keys (chapterIds) currently downloading to prevent constant DB queries
    // as the inner double values (progress) change on every chunk.
    final refreshTrigger = useState(0);

    final downloadingChaptersStr = ref.watch(
        nativeDownloadServiceProvider.select((state) => (state.keys.toList()..sort()).join(',')));

    final future = useMemoized(
      () => DownloadDatabase.instance.getAllChapters(),
      [downloadingChaptersStr, refreshTrigger.value],
    );

    final snapshot = useFuture(future);
    final appDirFuture = useMemoized(() => getApplicationDocumentsDirectory());
    final appDirSnapshot = useFuture(appDirFuture);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.downloads),
      ),
      body: Builder(
        builder: (context) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Emoticons(title: context.l10n.errorSomethingWentWrong);
          }

          final chapters = snapshot.data ?? [];
          if (chapters.isEmpty) {
            return Emoticons(title: context.l10n.noDownloads);
          }

          final appDir = appDirSnapshot.data;

          return ListView.builder(
            itemCount: chapters.length,
            itemBuilder: (context, index) {
              final chapter = chapters[index];
              return DownloadProgressTile(
                chapter: chapter,
                appDir: appDir,
                isDownloading: downloadingChaptersStr.split(',').contains('${chapter['chapterId']}'),
                onDeleted: () => refreshTrigger.value++,
              );
            },
          );
        },
      ),
    );
  }
}

class DownloadProgressTile extends HookConsumerWidget {
  final Map<String, dynamic> chapter;
  final Directory? appDir;
  final bool isDownloading;
  final VoidCallback onDeleted;

  const DownloadProgressTile({
    super.key,
    required this.chapter,
    this.appDir,
    required this.isDownloading,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mangaId = chapter['mangaId'] as int;
    final chapterId = chapter['chapterId'] as int;
    final chapterTitle = chapter['chapterTitle'] as String? ?? 'Unknown Chapter';
    final mangaTitle = chapter['mangaTitle'] as String? ?? 'Unknown Manga';
    final isDownloaded = chapter['downloadStatus'] == 1;

    // Granular progress check directly updates this specific tile without rebuilding the entire list
    final progress = isDownloading
        ? ref.watch(nativeDownloadServiceProvider.select((state) => state[chapterId]))
        : null;

    Widget leadingWidget = const Icon(Icons.download_done_rounded);

    if (appDir != null) {
      final coverPath = '${appDir!.path}/MangaDownloads/$mangaId/cover.jpg';
      final coverFile = File(coverPath);
      if (coverFile.existsSync()) {
        leadingWidget = ClipRRect(
          borderRadius: BorderRadius.circular(4.0),
          child: Image.file(
            coverFile,
            width: 50,
            height: 50,
            fit: BoxFit.cover,
          ),
        );
      }
    }

    return ListTile(
      leading: leadingWidget,
      title: Text(mangaTitle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(chapterTitle),
          const SizedBox(height: 4),
          if (isDownloaded)
            const Text(
              'Downloaded',
              style: TextStyle(color: Colors.green),
            )
          else if (isDownloading && progress != null)
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(value: progress),
                ),
                const SizedBox(width: 8),
                Text('${(progress * 100).toStringAsFixed(0)}%'),
              ],
            )
          else
            const Text(
              'Downloading...',
              style: TextStyle(color: Colors.orange),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDownloaded)
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () {
                ReaderRoute(
                  mangaId: mangaId,
                  chapterId: chapterId,
                  showReaderLayoutAnimation: true,
                ).push(context);
              },
            ),
          IconButton(
            icon: const Icon(Icons.delete_rounded),
            onPressed: () async {
              await ref
                  .read(nativeDownloadServiceProvider.notifier)
                  .deleteChapter(mangaId, chapterId);
              onDeleted();
            },
          ),
        ],
      ),
      onTap: isDownloaded
          ? () {
              ReaderRoute(
                mangaId: mangaId,
                chapterId: chapterId,
                showReaderLayoutAnimation: true,
              ).push(context);
            }
          : null,
    );
  }
}
