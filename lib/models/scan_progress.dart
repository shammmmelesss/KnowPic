/// 扫描阶段（对应文档 7.1 ScannerService / 9.1 冷启动引导）
enum ScanPhase {
  idle,
  reading, // 读取相册
  analyzing, // 提取特征（dHash + 128 维 + 美学分）
  clustering, // 聚类分组
  saving, // 持久化
  done,
  failed,
}

/// 扫描进度状态
class ScanProgress {
  const ScanProgress({
    this.phase = ScanPhase.idle,
    this.current = 0,
    this.total = 0,
    this.message = '',
    this.elapsedMs = 0,
  });

  final ScanPhase phase;
  final int current;
  final int total;
  final String message;
  final int elapsedMs;

  bool get isRunning =>
      phase == ScanPhase.reading ||
      phase == ScanPhase.analyzing ||
      phase == ScanPhase.clustering ||
      phase == ScanPhase.saving;

  double get fraction {
    if (total <= 0) return 0;
    return (current / total).clamp(0.0, 1.0);
  }

  ScanProgress copyWith({
    ScanPhase? phase,
    int? current,
    int? total,
    String? message,
    int? elapsedMs,
  }) {
    return ScanProgress(
      phase: phase ?? this.phase,
      current: current ?? this.current,
      total: total ?? this.total,
      message: message ?? this.message,
      elapsedMs: elapsedMs ?? this.elapsedMs,
    );
  }
}
