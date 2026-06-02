// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'koi_workspace_tile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_KoiWorkspaceTile _$KoiWorkspaceTileFromJson(Map<String, dynamic> json) =>
    _KoiWorkspaceTile(
      title: json['title'] as String,
      description: json['description'] as String,
      category: json['category'] as String,
      highlighted: json['highlighted'] as bool? ?? false,
    );

Map<String, dynamic> _$KoiWorkspaceTileToJson(_KoiWorkspaceTile instance) =>
    <String, dynamic>{
      'title': instance.title,
      'description': instance.description,
      'category': instance.category,
      'highlighted': instance.highlighted,
    };
