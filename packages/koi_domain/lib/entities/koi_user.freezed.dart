// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'koi_user.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$KoiUser {

 String get id; String get name; String get companyCode; String get role;
/// Create a copy of KoiUser
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$KoiUserCopyWith<KoiUser> get copyWith => _$KoiUserCopyWithImpl<KoiUser>(this as KoiUser, _$identity);

  /// Serializes this KoiUser to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is KoiUser&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.companyCode, companyCode) || other.companyCode == companyCode)&&(identical(other.role, role) || other.role == role));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,companyCode,role);

@override
String toString() {
  return 'KoiUser(id: $id, name: $name, companyCode: $companyCode, role: $role)';
}


}

/// @nodoc
abstract mixin class $KoiUserCopyWith<$Res>  {
  factory $KoiUserCopyWith(KoiUser value, $Res Function(KoiUser) _then) = _$KoiUserCopyWithImpl;
@useResult
$Res call({
 String id, String name, String companyCode, String role
});




}
/// @nodoc
class _$KoiUserCopyWithImpl<$Res>
    implements $KoiUserCopyWith<$Res> {
  _$KoiUserCopyWithImpl(this._self, this._then);

  final KoiUser _self;
  final $Res Function(KoiUser) _then;

/// Create a copy of KoiUser
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? companyCode = null,Object? role = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,companyCode: null == companyCode ? _self.companyCode : companyCode // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [KoiUser].
extension KoiUserPatterns on KoiUser {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _KoiUser value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _KoiUser() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _KoiUser value)  $default,){
final _that = this;
switch (_that) {
case _KoiUser():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _KoiUser value)?  $default,){
final _that = this;
switch (_that) {
case _KoiUser() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String companyCode,  String role)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _KoiUser() when $default != null:
return $default(_that.id,_that.name,_that.companyCode,_that.role);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String companyCode,  String role)  $default,) {final _that = this;
switch (_that) {
case _KoiUser():
return $default(_that.id,_that.name,_that.companyCode,_that.role);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String companyCode,  String role)?  $default,) {final _that = this;
switch (_that) {
case _KoiUser() when $default != null:
return $default(_that.id,_that.name,_that.companyCode,_that.role);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class _KoiUser extends KoiUser {
  const _KoiUser({required this.id, required this.name, required this.companyCode, required this.role}): super._();
  factory _KoiUser.fromJson(Map<String, dynamic> json) => _$KoiUserFromJson(json);

@override final  String id;
@override final  String name;
@override final  String companyCode;
@override final  String role;

/// Create a copy of KoiUser
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$KoiUserCopyWith<_KoiUser> get copyWith => __$KoiUserCopyWithImpl<_KoiUser>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$KoiUserToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _KoiUser&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.companyCode, companyCode) || other.companyCode == companyCode)&&(identical(other.role, role) || other.role == role));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,companyCode,role);

@override
String toString() {
  return 'KoiUser(id: $id, name: $name, companyCode: $companyCode, role: $role)';
}


}

/// @nodoc
abstract mixin class _$KoiUserCopyWith<$Res> implements $KoiUserCopyWith<$Res> {
  factory _$KoiUserCopyWith(_KoiUser value, $Res Function(_KoiUser) _then) = __$KoiUserCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String companyCode, String role
});




}
/// @nodoc
class __$KoiUserCopyWithImpl<$Res>
    implements _$KoiUserCopyWith<$Res> {
  __$KoiUserCopyWithImpl(this._self, this._then);

  final _KoiUser _self;
  final $Res Function(_KoiUser) _then;

/// Create a copy of KoiUser
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? companyCode = null,Object? role = null,}) {
  return _then(_KoiUser(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,companyCode: null == companyCode ? _self.companyCode : companyCode // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
