import '../core/constants.dart';
import '../core/logger.dart';
import '../models/preference_model.dart';
import '../models/user_action.dart';
import 'metadata_store.dart';

/// 偏好学习服务（对应文档 7.5 LearningService / 8.2 学习闭环）
/// - 行为样本暂存内存队列，满 200 条刷盘（文档 7.5）
/// - 成对学习（BPR）：正样本得分高于负样本
/// - 反漏斗挽救：连续 5 组否决 AI 最佳 → 提示重置（文档 9.4）
class LearningService {
  LearningService(this._store);

  final MetadataStore _store;
  final List<UserAction> _buffer = [];

  /// 连续否决 AI 推荐的组数
  int consecutiveRejections = 0;
  bool _resetPromptPending = false;

  /// 全局汇总偏好模型（UI 展示用）
  PreferenceModel get model =>
      _store.preferences[AppConfig.defaultScene] ??
      _store.scenePreference(AppConfig.defaultScene);

  /// 所有场景模型（settings 页展示）
  Map<String, PreferenceModel> get models => _store.preferences;

  /// 按场景取独立偏好模型（文档 8.1 多场景偏好）
  PreferenceModel modelFor(String sceneType) =>
      _store.scenePreference(sceneType);

  /// 记录一次行为（隐式/显式反馈）
  void collect(UserAction action) {
    _buffer.add(action);
    if (_buffer.length >= AppConfig.feedbackFlushThreshold) {
      flush(); // 达到阈值触发刷盘
    }
  }

  /// 把行为队列用于训练并清空（文档 7.5：充电+WiFi 闲时触发；本处为应用内立即训练）
  Future<void> flush() async {
    if (_buffer.isEmpty) return;
    final positives = _buffer.where((a) => a.isPositive).toList();
    final negatives = _buffer.where((a) => !a.isPositive).toList();
    if (positives.isNotEmpty && negatives.isNotEmpty) {
      var trained = 0;
      for (final pos in positives) {
        final fPos = _store.assetFeatures(pos.assetId);
        if (fPos == null) continue;
        // 正样本属于哪个场景，就训练哪个场景的独立模型（文档 8.1）
        final scene = _store.assets[pos.assetId]?.sceneType ?? AppConfig.sceneOther;
        final sceneModel = modelFor(scene);
        // 每个正样本与最多 5 个负样本配对（BPR）
        for (final neg in negatives.take(5)) {
          final fNeg = _store.assetFeatures(neg.assetId);
          if (fNeg == null) continue;
          final w = (pos.weight + neg.weight) / 2;
          sceneModel.updatePair(fPos.toList(), fNeg.toList(), w);
          // 全局汇总模型同步学习，用于 UI 展示与冷启动兜底
          if (!identical(model, sceneModel)) {
            model.updatePair(fPos.toList(), fNeg.toList(), w);
          }
          trained++;
        }
      }
      Log.d('Learning', 'trained pairs=$trained scenes=${_store.preferences.length}');
    }
    _buffer.clear();
    await _store.savePref();
  }

  /// 记录一个组的处理结果，用于反漏斗追踪
  void recordGroupOutcome(String groupId, String bestId, List<String> keptIds) {
    if (keptIds.contains(bestId)) {
      consecutiveRejections = 0; // 采纳了推荐
    } else {
      consecutiveRejections++; // 否决了推荐
      Log.d('Learning', 'rejection streak=$consecutiveRejections');
    }
    if (consecutiveRejections >= AppConfig.resetStreakThreshold) {
      _resetPromptPending = true;
    }
  }

  /// 消费重置提示（UI 弹窗）
  bool consumeResetPrompt() {
    final v = _resetPromptPending;
    _resetPromptPending = false;
    return v;
  }

  /// 确认重置偏好（文档 9.4 响应动作）：重置全部场景模型
  Future<void> confirmReset() async {
    for (final m in _store.preferences.values) {
      m.reset();
    }
    consecutiveRejections = 0;
    _resetPromptPending = false;
    await _store.savePref();
    Log.d('Learning', 'preferences reset scenes=${_store.preferences.length}');
  }
}
