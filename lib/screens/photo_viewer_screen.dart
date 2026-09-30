import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/ios_design.dart';
import '../models/photo_asset.dart';
import '../widgets/photo_thumb.dart';

/// 全屏照片预览：左右翻页 + 双指/双击缩放。
/// 用于相似组内放大对比细节（判断保留哪张的核心依据），
/// 以及首页/记忆页点开单张查看。
class PhotoViewerScreen extends ConsumerStatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.assets,
    this.initialIndex = 0,
    this.onZoomed,
  });

  final List<PhotoAsset> assets;
  final int initialIndex;

  /// 真正发生放大时回调（用于采集强正样本，替代此前"假装放大"的反馈）
  final void Function(PhotoAsset asset)? onZoomed;

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  late final PageController _page;
  late int _index;

  /// 当前页是否处于放大状态：放大时禁用翻页，避免拖动手势与翻页打架
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _index = widget.assets.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.assets.length - 1);
    _page = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.assets.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }
    final asset = widget.assets[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _page,
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: widget.assets.length,
            onPageChanged: (i) => setState(() {
              _index = i;
              _zoomed = false;
            }),
            itemBuilder: (context, i) => _ZoomablePhoto(
              key: ValueKey(widget.assets[i].id),
              asset: widget.assets[i],
              active: i == _index,
              onZoomChanged: (z) {
                // 手势与动画回调都在帧间触发；仍做一次守卫，
                // 避免任何构建期调用导致父级 setState during build
                if (!mounted || i != _index || z == _zoomed) return;
                setState(() => _zoomed = z);
              },
              onZoomed: widget.onZoomed,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopBar(
              index: _index,
              total: widget.assets.length,
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
          _InfoBar(asset: asset),
        ],
      ),
    );
  }
}

/// 顶部：关闭 + 位置指示
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.index,
    required this.total,
    required this.onClose,
  });

  final int index;
  final int total;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 52,
                height: 44,
                child: IconButton(
                  icon: const Icon(CupertinoIcons.xmark,
                      color: Colors.white, size: 22),
                  tooltip: '关闭',
                  onPressed: onClose,
                ),
              ),
            ),
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${index + 1} / $total',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部：拍摄时间与文件名
class _InfoBar extends StatelessWidget {
  const _InfoBar({required this.asset});

  final PhotoAsset asset;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateFormat('yyyy年M月d日 HH:mm').format(asset.createdTime),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (asset.title.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              asset.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
          if (asset.width > 0 && asset.height > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${asset.width} × ${asset.height} · ${Ios.formatBytes(asset.byteSize)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单张可缩放照片：双指缩放 + 双击在 1x 与 2.5x 间切换
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    super.key,
    required this.asset,
    required this.active,
    required this.onZoomChanged,
    this.onZoomed,
  });

  final PhotoAsset asset;
  final bool active;
  final ValueChanged<bool> onZoomChanged;
  final void Function(PhotoAsset asset)? onZoomed;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  static const double _doubleTapScale = 2.5;
  static const double _zoomedThreshold = 1.01;

  final _controller = TransformationController();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final CurvedAnimation _zoomCurve =
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
  Animation<Matrix4>? _zoomAnim;
  Offset? _doubleTapPosition;
  bool _notifiedZoomed = false;

  bool get _isZoomed => _controller.value.getMaxScaleOnAxis() > _zoomedThreshold;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransformChanged);
    _anim.addListener(() {
      final a = _zoomAnim;
      if (a != null) _controller.value = a.value;
    });
  }

  @override
  void didUpdateWidget(_ZoomablePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 翻走时复位缩放，回来仍是 1x。这里临时摘掉监听器：
    // didUpdateWidget 处于父级构建期，此时回调父级 setState 会报错。
    if (oldWidget.active && !widget.active && _isZoomed) {
      _anim.stop();
      _zoomAnim = null;
      _controller.removeListener(_onTransformChanged);
      _controller.value = Matrix4.identity();
      _controller.addListener(_onTransformChanged);
      _notifiedZoomed = false;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    _controller.dispose();
    _zoomCurve.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _isZoomed;
    if (zoomed == _notifiedZoomed) return; // 只在状态翻转时通知，避免每帧重建
    _notifiedZoomed = zoomed;
    widget.onZoomChanged(zoomed);
  }

  void _handleDoubleTapDown(TapDownDetails details) =>
      _doubleTapPosition = details.localPosition;

  void _handleDoubleTap() {
    if (_isZoomed) {
      _animateTo(Matrix4.identity());
      return;
    }
    // 以点击点为中心放大：先把该点平移回原点再缩放，松手后该点位置不变
    _animateTo(_scaleAboutPoint(_doubleTapScale, _doubleTapPosition));
    widget.onZoomed?.call(widget.asset);
  }

  /// 构造「以 [point] 为中心缩放 [scale] 倍」的变换矩阵。
  /// 直接写矩阵元素而非链式 translate/scale，避免依赖会被弃用的重载。
  Matrix4 _scaleAboutPoint(double scale, Offset? point) {
    final dx = point == null ? 0.0 : -point.dx * (scale - 1);
    final dy = point == null ? 0.0 : -point.dy * (scale - 1);
    return Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, dx)
      ..setEntry(1, 3, dy);
  }

  void _animateTo(Matrix4 target) {
    // clone：TransformationController 的矩阵会被手势就地修改，
    // 直接引用会让动画起点跟着变
    _zoomAnim =
        Matrix4Tween(begin: _controller.value.clone(), end: target).animate(
      _zoomCurve,
    );
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 4,
        child: SizedBox.expand(
          // 预览用更大尺寸解码：列表用的 512 在全屏下会明显发虚
          child: PhotoThumb(
            assetId: widget.asset.id,
            fit: BoxFit.contain,
            size: 1024,
          ),
        ),
      ),
    );
  }
}
