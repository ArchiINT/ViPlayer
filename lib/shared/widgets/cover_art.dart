import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Album/track artwork with rounded corners and a quiet placeholder when
/// there is no image.
///
/// Images are decoded at the displayed size (`cacheWidth`), not their full
/// resolution — keeps long lists smooth and memory low.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.path,
    required this.size,
    this.radius = AppRadius.small,
    this.elevated = false,
  });

  final String? path;
  final double size;
  final double radius;

  /// Soft drop shadow — only for single hero covers, never in lists.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final pixelSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final borderRadius = BorderRadius.circular(radius);

    final image = path == null
        ? _Placeholder(size: size)
        : Image(
            // Remote tracks (streamed from another device) have URL covers.
            image: ResizeImage(
              path!.startsWith('http')
                  ? NetworkImage(path!)
                  : FileImage(File(path!)) as ImageProvider,
              width: pixelSize,
            ),
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            frameBuilder: (context, child, frame, sync) => sync
                ? child
                : AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: AppMotion.fast,
                    child: child,
                  ),
            errorBuilder: (_, _, _) => _Placeholder(size: size),
          );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.glassStrong,
        borderRadius: borderRadius,
        boxShadow: elevated
            ? const [
                BoxShadow(
                  color: Color(0x80000000),
                  blurRadius: 32,
                  offset: Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: ClipRRect(borderRadius: borderRadius, child: image),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.4,
        color: AppColors.textTertiary,
      ),
    );
  }
}
