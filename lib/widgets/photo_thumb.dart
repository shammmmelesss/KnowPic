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
  /// LRU 内存缓存（上限 256 张 ≈ 10MB），避免大图库无限增长
  static final _cache = _LruCache<String, Uint8List>(256);

  /// 并发去重：同一资产只发起一次加载
  static final _inflight = <String, Future<Uint8List?>>{};

  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    final cached = _cache.get(widget.assetId);
    if (cached != null) {
      _bytes = cached;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    // 已有相同资产的加载在进行中 → 复用
    final existing = _inflight[widget.assetId];
    if (existing != null) {
      final bytes = await existing;
      if (mounted) setState(() => _bytes = bytes);
      return;
    }
    final future = ref
        .read(libraryProvider)
        .loadThumbnail(widget.assetId)
        .then((bytes) {
      if (bytes != null) _cache.put(widget.assetId, bytes);
      return bytes;
    }).whenComplete(() => _inflight.remove(widget.assetId));
    _inflight[widget.assetId] = future;
    final bytes = await future;
    if (mounted) setState(() => _bytes = bytes);
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

/// 极简 LRU：LinkedHashMap 保持插入序，命中即重新插入，超限淘汰最旧项
class _LruCache<K, V> {
  _LruCache(this.maxSize) : assert(maxSize > 0);

  final int maxSize;
  final _map = <K, V>{};

  V? get(K key) {
    final v = _map.remove(key);
    if (v != null) _map[key] = v; // 重新插入 → 移到"最新"端
    return v;
  }

  void put(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > maxSize) {
      _map.remove(_map.keys.first);
    }
  }
}
