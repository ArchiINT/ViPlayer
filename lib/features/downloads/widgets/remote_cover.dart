import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// Artwork from the web (link previews), decoded at display size, with a
/// quiet placeholder while loading or when there is none. YouTube's 16:9
/// thumbnails are center-cropped to a square, like the saved cover.
class RemoteCover extends StatelessWidget {
  const RemoteCover({super.key, required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = SizedBox.square(
      dimension: size,
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.4,
        color: AppColors.textTertiary,
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.glassStrong,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              fit: BoxFit.cover,
              cacheHeight: (size * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              errorBuilder: (_, _, _) => placeholder,
              frameBuilder: (context, child, frame, sync) => sync
                  ? child
                  : AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: AppMotion.fast,
                      child: child,
                    ),
            ),
    );
  }
}
