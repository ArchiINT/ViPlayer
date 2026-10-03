import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Full-bleed backdrop behind the glass UI: the artwork, heavily "blurred",
/// under a dark scrim — or a soft accent-coloured aura when there is no art.
///
/// Performance: no blur filter is involved. The cover is decoded at a tiny
/// size ([_sampleSize] px) and stretched with smooth filtering, which looks
/// like a strong blur but costs nothing per frame (a real blur would be
/// re-rendered every frame by Impeller). Cover changes cross-fade.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, this.coverPath});

  final String? coverPath;

  static const _sampleSize = 12;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.base),
          AnimatedSwitcher(
            duration: AppMotion.slow,
            // Children must fill the screen; the default layout would show
            // the 12 px artwork at its natural (tiny) size.
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: coverPath == null
                ? _Aura(key: ValueKey(accent), accent: accent)
                : _StretchedArt(key: ValueKey(coverPath), path: coverPath!),
          ),
          // Scrim: keeps text readable on any artwork.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x33000000), Color(0x99000000)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StretchedArt extends StatelessWidget {
  const _StretchedArt({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final source = path.startsWith('http')
        ? NetworkImage(path)
        : FileImage(File(path)) as ImageProvider;
    return Image(
      image: ResizeImage(source, width: AmbientBackground._sampleSize),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (context, _, _) =>
          _Aura(accent: Theme.of(context).colorScheme.primary),
    );
  }
}

/// Two soft light pools in the accent colour.
class _Aura extends StatelessWidget {
  const _Aura({super.key, required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final second = HSLColor.fromColor(accent)
        .withHue((HSLColor.fromColor(accent).hue + 60) % 360)
        .toColor();
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.9, -1),
              radius: 1.3,
              colors: [accent.withValues(alpha: 0.6), Colors.transparent],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1, 0.9),
              radius: 1.2,
              colors: [second.withValues(alpha: 0.45), Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }
}
