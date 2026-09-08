import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

/// 相册缩略图（带内存缓存，避免重复加载；文档 11：绝不加载原图）
class PhotoThumb extends ConsumerStatefulWidget {
  const PhotoThumb({
    super.key,
    required this.assetId,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
  });

  final String assetId;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  ConsumerState<PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends ConsumerState<PhotoThumb> {
  static final Map<String, Uint8List> _cache = {};
  Uint8List? _bytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final cached = _cache[widget.assetId];
    if (cached != null) {
      _bytes = cached;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    final bytes = await ref.read(libraryProvider).loadThumbnail(widget.assetId);
    if (bytes != null) {
      _cache[widget.assetId] = bytes;
    }
    if (mounted) {
      setState(() => _bytes = bytes);
    }
    _loading = false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Widget child;
    if (_bytes != null) {
      child = Image.memory(
        _bytes!,
        fit: widget.fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
    } else {
      // iOS 相册风格：占位灰块，不做加载动画
      child = Container(color: colorScheme.surfaceContainerHighest);
    }
    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }
    return child;
  }
}
