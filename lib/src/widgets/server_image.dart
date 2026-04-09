// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../constants/app_sizes.dart';
import '../constants/endpoints.dart';
import '../constants/enum.dart';
import '../features/settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../features/settings/presentation/server/widget/client/server_tunnel_tile.dart';
import '../features/settings/presentation/server/widget/client/server_tunnel_url_tile.dart';
import '../features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../global_providers/global_providers.dart';
import '../utils/extensions/custom_extensions.dart';
import '../utils/logger/logger.dart';
import '../utils/misc/app_utils.dart';
import 'custom_circular_progress_indicator.dart';

class ServerImage extends HookConsumerWidget {
  const ServerImage({
    super.key,
    required this.imageUrl,
    this.size,
    this.fit,
    this.appendApiToUrl = false,
    this.progressIndicatorBuilder,
    this.wrapper,
    this.showReloadButton = false,
    this.mangaId,
    this.chapterId,
    this.pageIndex,
  });

  final String imageUrl;
  final Size? size;
  final BoxFit? fit;
  final bool appendApiToUrl;
  final Widget Function(BuildContext, String, DownloadProgress)?
      progressIndicatorBuilder;
  final Widget Function(Widget child)? wrapper;
  final bool showReloadButton;

  // Optional parameters for checking local native downloads
  final int? mangaId;
  final int? chapterId;
  final int? pageIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = useState(UniqueKey());
    final localFile = useState<File?>(null);
    final isCheckingLocal = useState<bool>(true);

    // Providers
    final authType = ref.watch(authTypeKeyProvider);
    final basicToken = ref.watch(credentialsProvider);

    useEffect(() {
      Future<void> checkLocal() async {
        if (imageUrl.startsWith('file://')) {
          final potentialFile = File(imageUrl.replaceFirst('file://', ''));
          if (await potentialFile.exists()) {
             localFile.value = potentialFile;
          } else {
             logger.e('ServerImage expected local file missing: ${potentialFile.path}');
          }
        } else if (mangaId != null && chapterId != null && pageIndex != null) {
          try {
            final appDir = await getApplicationDocumentsDirectory();
            final uri = Uri.parse(imageUrl);
            final ext = uri.pathSegments.isNotEmpty ? uri.pathSegments.last.split('.').last : 'jpg';
            final validExt = ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext.toLowerCase()) ? ext : 'jpg';

            // Note: fallback hardcoded to native_downloads since downloads was temporary.
            // Better to rely on the file:// absolute url scheme from ReaderController now.
            final potentialFile = File('${appDir.path}/native_downloads/$mangaId/$chapterId/$pageIndex.$validExt');
            if (await potentialFile.exists()) {
              localFile.value = potentialFile;
            }
          } catch (e) {
            // Error checking local, fallback to network
          }
        }
        isCheckingLocal.value = false;
      }

      checkLocal();
      return null;
    }, [imageUrl, mangaId, chapterId, pageIndex]);

    final baseApi = "${Endpoints.baseApi(
      baseUrl: ref.watch(serverUrlProvider),
      port: ref.watch(serverPortProvider),
      addPort: ref.watch(serverPortToggleProvider).ifNull(),
      isTunnel: ref.watch(serverTunnelToggleProvider).ifNull(),
      tunnelUrl: ref.watch(serverTunnelUrlProvider),
      appendApiToUrl: appendApiToUrl,
    )}"
        "$imageUrl";

    final Map<String, String>? httpHeaders =
        (authType == AuthType.basic && basicToken != null)
            ? ({"Authorization": basicToken})
            : null;

    final ImageRenderMethodForWeb renderMethod;
    if (authType == AuthType.basic && basicToken != null) {
      renderMethod = ImageRenderMethodForWeb.HttpGet;
    } else {
      renderMethod = ImageRenderMethodForWeb.HtmlImage;
    }

    finalProgressIndicatorBuilder(
            BuildContext context, String url, DownloadProgress progress) =>
        AppUtils.wrapOn(
          wrapper,
          progressIndicatorBuilder?.call(context, url, progress) ??
              const CenterSorayomiShimmerIndicator(),
        );

    Widget errorWidget(BuildContext context, String error, stackTrace) {
      if (showReloadButton) {
        return AppUtils.wrapOn(
          wrapper,
          Padding(
            padding: KEdgeInsets.a8.size,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.broken_image_rounded,
                    color: Colors.grey,
                  ),
                  const Gap(32),
                  TextButton(
                    onPressed: () {
                      key.value = (UniqueKey());
                    },
                    child: Text(context.l10n.reload),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        return AppUtils.wrapOn(
          wrapper,
          const Icon(
            Icons.broken_image_rounded,
            color: Colors.grey,
          ),
        );
      }
    }

    if (isCheckingLocal.value) {
      return AppUtils.wrapOn(
        wrapper,
        progressIndicatorBuilder?.call(context, imageUrl, DownloadProgress(imageUrl, null, 0)) ??
            const CenterSorayomiShimmerIndicator(),
      );
    }

    if (localFile.value != null) {
      return AppUtils.wrapOn(
        wrapper,
        Image.file(
          localFile.value!,
          key: key.value,
          height: size?.height,
          width: size?.width,
          fit: fit ?? BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => errorWidget(context, error.toString(), stackTrace),
        ),
      );
    }

    return CachedNetworkImage(
      key: key.value,
      imageUrl: baseApi,
      height: size?.height,
      cacheManager: DefaultCacheManager(),
      httpHeaders: httpHeaders,
      width: size?.width,
      fit: fit ?? BoxFit.cover,
      imageRenderMethodForWeb: renderMethod,
      progressIndicatorBuilder: finalProgressIndicatorBuilder,
      errorWidget: errorWidget,
    );
  }
}

class ServerImageWithCpi extends StatelessWidget {
  const ServerImageWithCpi({
    super.key,
    required this.url,
    required this.outerSize,
    required this.innerSize,
    required this.isLoading,
  });
  final bool isLoading;
  final Size outerSize;
  final Size innerSize;
  final String url;
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox.fromSize(
        size: outerSize,
        child: Stack(
          alignment: AlignmentDirectional.center,
          children: [
            const Padding(
              padding: EdgeInsets.all(4.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            ServerImage(
              imageUrl: url,
              size: innerSize,
              progressIndicatorBuilder: (context, url, progress) =>
                  const CenterSorayomiShimmerIndicator(),
            )
          ],
        ),
      );
    } else {
      return ServerImage(imageUrl: url, size: outerSize);
    }
  }
}
