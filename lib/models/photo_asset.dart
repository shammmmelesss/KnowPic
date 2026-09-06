import 'dart:typed_data';

import '../core/constants.dart';

/// 图片资产（对应文档 6.2 Asset）。
/// 与 photo_manager 的 AssetEntity 解耦，便于单元测试。
class PhotoAsset {
  PhotoAsset({
    required this.id,
    required this.title,
    required this.width,
    required this.height,
    required this.byteSize,
    required this.createdTime,
    this.isLivePhoto = false,
    this.isCloudPlaceholder = false,
    this.dHash = 0,
    Float32List? features,
    this.baseScore = 0,
    this.sceneType = 'other',
    this.finalScore = 0,
    this.faceCount = 0,
    this.eyeOpenScore = 0,
    this.smileScore = 0,
    this.decisiveScore = 0,
  }) : features = features ?? Float32List(AppConfig.featureDim);

  final String id;
  final String title;
  final int width;
  final int height;
  final int byteSize;
  final DateTime createdTime;
  final bool isLivePhoto;
  final bool isCloudPlaceholder;

  int dHash; // 64 位感知哈希
  Float32List features; // 128 维特征
  double baseScore; // NIMA 客观美学分（0-10）
  String sceneType; // portrait | landscape | document | food | other
  double finalScore; // 综合分（客观+个人偏好）
  int faceCount; // 检测到的人脸数
  double eyeOpenScore; // 0-1 睁眼估计
  double smileScore; // 0-1 微笑估计
  double decisiveScore; // 0-1 决定性瞬间（连拍推荐）

  double get aspectRatio => height == 0 ? 0 : width / height;

  bool get isLongShot =>
      aspectRatio > AppConfig.longShotAspectRatio ||
      aspectRatio < 1 / AppConfig.longShotAspectRatio;

  PhotoAsset copyWith({
    int? dHash,
    Float32List? features,
    double? baseScore,
    String? sceneType,
    double? finalScore,
    int? faceCount,
    double? eyeOpenScore,
    double? smileScore,
    double? decisiveScore,
  }) {
    return PhotoAsset(
      id: id,
      title: title,
      width: width,
      height: height,
      byteSize: byteSize,
      createdTime: createdTime,
      isLivePhoto: isLivePhoto,
      isCloudPlaceholder: isCloudPlaceholder,
      dHash: dHash ?? this.dHash,
      features: features ?? this.features,
      baseScore: baseScore ?? this.baseScore,
      sceneType: sceneType ?? this.sceneType,
      finalScore: finalScore ?? this.finalScore,
      faceCount: faceCount ?? this.faceCount,
      eyeOpenScore: eyeOpenScore ?? this.eyeOpenScore,
      smileScore: smileScore ?? this.smileScore,
      decisiveScore: decisiveScore ?? this.decisiveScore,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'width': width,
        'height': height,
        'byteSize': byteSize,
        'createdTime': createdTime.toIso8601String(),
        'isLivePhoto': isLivePhoto,
        'isCloudPlaceholder': isCloudPlaceholder,
        'dHash': dHash,
        'baseScore': baseScore,
        'sceneType': sceneType,
        'finalScore': finalScore,
        'faceCount': faceCount,
        'eyeOpenScore': eyeOpenScore,
        'smileScore': smileScore,
        'decisiveScore': decisiveScore,
      };

  factory PhotoAsset.fromJson(Map<String, dynamic> json) {
    return PhotoAsset(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      width: json['width'] as int? ?? 0,
      height: json['height'] as int? ?? 0,
      byteSize: json['byteSize'] as int? ?? 0,
      createdTime: DateTime.tryParse(json['createdTime'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isLivePhoto: json['isLivePhoto'] as bool? ?? false,
      isCloudPlaceholder: json['isCloudPlaceholder'] as bool? ?? false,
      dHash: json['dHash'] as int? ?? 0,
      baseScore: (json['baseScore'] as num?)?.toDouble() ?? 0,
      sceneType: json['sceneType'] as String? ?? 'other',
      finalScore: (json['finalScore'] as num?)?.toDouble() ?? 0,
      faceCount: json['faceCount'] as int? ?? 0,
      eyeOpenScore: (json['eyeOpenScore'] as num?)?.toDouble() ?? 0,
      smileScore: (json['smileScore'] as num?)?.toDouble() ?? 0,
      decisiveScore: (json['decisiveScore'] as num?)?.toDouble() ?? 0,
    );
  }
}
