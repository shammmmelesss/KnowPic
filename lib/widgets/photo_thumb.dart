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
    this.size = 512,
  });

  final String assetId;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  /// 向相册请求的解码边长：列表用 512，全屏预览传更大值，特征分析走 256
  final int size;

  @override
  ConsumerState<PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends ConsumerState<PhotoThumb> {
  /// LRU 内存缓存（上限 256 张 ≈ 10MB），避免大图库无限增长
  static final _cache = _LruCache<String, Uint8List>(256);

  /// 并发去重：同一资产同一尺寸只发起一次加载
  static final _inflight = <String, Future<Uint8List?>>{};

  Uint8List? _bytes;

  /// 缓存键带上请求尺寸：同一资产在不同尺寸下是两份数据，不能互相顶替
  String get _cacheKey => '${widget.assetId}@${widget.size}';

  @override
  void initState() {
    super.initState();
    final cached = _cache.get(_cacheKey);
    if (cached != null) {
      _bytes = cached;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(PhotoThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 列表增删/排序后，同一 Element 会被换绑到另一张照片（调用点若未传 key
    // 即按位置复用）。此处必须按新 assetId 重新取图，否则会继续显示上一张照片。
    if (oldWidget.assetId != widget.assetId || oldWidget.size != widget.size) {
      // 紧随其后的 build 会读取 _bytes，直接赋值即可，无需 setState
      _bytes = _cache.get(_cacheKey);
      if (_bytes == null) _load();
    }
  }

  Future<void> _load() async {
    final key = _cacheKey;
    // 已有相同资产的加载在进行中 → 复用
    final existing = _inflight[key];
    if (existing != null) {
      final bytes = await existing;
      if (mounted && key == _cacheKey) setState(() => _bytes = bytes);
      return;
    }
    final future = ref
        .read(libraryProvider)
        .loadThumbnail(widget.assetId, size: widget.size)
        .then((bytes) {
      if (bytes != null) _cache.put(key, bytes);
      return bytes;
    }).whenComplete(() => _inflight.remove(key));
    _inflight[key] = future;
    final bytes = await future;
    if (mounted && key == _cacheKey) setState(() => _bytes = bytes);
  }

  /// 解码尺寸按实际显示尺寸降采样：请求 512 却只显示 100pt 时，
  /// 不限制解码尺寸会把整张缩略图（乃至原图）展开成位图常驻 ImageCache。
  int? _decodeWidth(BuildContext context, BoxConstraints constraints) {
    final logical = widget.width ??
        (constraints.maxWidth.isFinite ? constraints.maxWidth : null) ??
        widget.height ??
        (constraints.maxHeight.isFinite ? constraints.maxHeight : null);
    if (logical == null || logical <= 0) return null;
    final px = (logical * MediaQuery.devicePixelRatioOf(context)).round();
    if (px <= 0 || px >= widget.size) return null; // 请求尺寸已经够小，无需再约束
    return px;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bytes = _bytes;
    final Widget child;
    if (bytes != null) {
      child = LayoutBuilder(
        builder: (context, constraints) => Image.memory(
          bytes,
          fit: widget.fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          cacheWidth: _decodeWidth(context, constraints),
        ),
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
