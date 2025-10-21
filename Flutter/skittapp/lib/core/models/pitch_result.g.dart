// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pitch_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PitchResult _$PitchResultFromJson(Map<String, dynamic> json) => PitchResult(
  f0: (json['f0'] as num?)?.toDouble(),
  confidence: (json['confidence'] as num).toDouble(),
  note: json['note'] as String?,
  cents: (json['cents'] as num?)?.toDouble(),
);

Map<String, dynamic> _$PitchResultToJson(PitchResult instance) =>
    <String, dynamic>{
      'f0': instance.f0,
      'confidence': instance.confidence,
      'note': instance.note,
      'cents': instance.cents,
    };
