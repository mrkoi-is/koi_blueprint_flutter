// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'koi_user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_KoiUser _$KoiUserFromJson(Map<String, dynamic> json) => _KoiUser(
  id: json['id'] as String,
  name: json['name'] as String,
  companyCode: json['company_code'] as String,
  role: json['role'] as String,
);

Map<String, dynamic> _$KoiUserToJson(_KoiUser instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'company_code': instance.companyCode,
  'role': instance.role,
};
