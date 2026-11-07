import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/content_assets.dart';

/// A delivered content-kit picture or animation (animated WebP loops by itself), or the
/// fallback when that ID has not been delivered yet.
class ContentPicture extends StatelessWidget {
  final String id;
  final Widget fallback;
  final double? height;
  final BoxFit fit;
  final double radius;

  /// What the picture shows, for screen readers. Without it the picture is decorative.
  final String? semanticLabel;
  const ContentPicture(this.id, {super.key, required this.fallback, this.height, this.fit = BoxFit.cover, this.radius = 16, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final a = ContentAssets.get(id);
    if (a == null || a.path.isEmpty || a.type == 'video') return fallback;
    final img = a.path.endsWith('.svg')
        ? SvgPicture.asset(a.path, fit: fit, height: height)
        : Image.asset(
            a.path,
            fit: fit,
            height: height,
            width: double.infinity,
            gaplessPlayback: true,
            semanticLabel: semanticLabel,
            excludeFromSemantics: semanticLabel == null,
            errorBuilder: (_, _, _) => fallback,
          );
    return ClipRRect(
      key: Key('content-$id'),
      borderRadius: BorderRadius.circular(radius),
      child: height == null ? AspectRatio(aspectRatio: 4 / 3, child: img) : SizedBox(height: height, child: img),
    );
  }
}

/// A delivered one-colour icon (SVG or PNG), tinted to the level colour; else a Material icon.
class ContentIcon extends StatelessWidget {
  final String? id;
  final IconData fallback;
  final Color color;
  final double size;
  const ContentIcon(this.id, this.fallback, {super.key, required this.color, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final a = id == null ? null : ContentAssets.get(id!);
    if (a == null || a.path.isEmpty) return Icon(fallback, color: color, size: size);
    if (a.path.endsWith('.svg')) {
      return SvgPicture.asset(a.path, width: size, height: size, colorFilter: ColorFilter.mode(color, BlendMode.srcIn));
    }
    return Image.asset(a.path, width: size, height: size, color: color, colorBlendMode: BlendMode.srcIn);
  }
}
