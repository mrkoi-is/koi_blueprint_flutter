// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'koi_workspace_tile.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$KoiWorkspaceTile {

 String get title; String get description; String get category; bool get highlighted;
/// Create a copy of KoiWorkspaceTile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$KoiWorkspaceTileCopyWith<KoiWorkspaceTile> get copyWith => _$KoiWorkspaceTileCopyWithImpl<KoiWorkspaceTile>(this as KoiWorkspaceTile, _$identity);

  /// Serializes this KoiWorkspaceTile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is KoiWorkspaceTile&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.category, category) || other.category == category)&&(identical(other.highlighted, highlighted) || other.highlighted == highlighted));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,title,description,category,highlighted);

@override
String toString() {
  return 'KoiWorkspaceTile(title: $title, description: $description, category: $category, highlighted: $highlighted)';
}


}

/// @nodoc
abstract mixin class $KoiWorkspaceTileCopyWith<$Res>  {
  factory $KoiWorkspaceTileCopyWith(KoiWorkspaceTile value, $Res Function(KoiWorkspaceTile) _then) = _$KoiWorkspaceTileCopyWithImpl;
@useResult
$Res call({
 String title, String description, String category, bool highlighted
});




}
/// @nodoc
class _$KoiWorkspaceTileCopyWithImpl<$Res>
    implements $KoiWorkspaceTileCopyWith<$Res> {
  _$KoiWorkspaceTileCopyWithImpl(this._self, this._then);

  final KoiWorkspaceTile _self;
  final $Res Function(KoiWorkspaceTile) _then;

/// Create a copy of KoiWorkspaceTile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? title = null,Object? description = null,Object? category = null,Object? highlighted = null,}) {
  return _then(_self.copyWith(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,highlighted: null == highlighted ? _self.highlighted : highlighted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [KoiWorkspaceTile].
extension KoiWorkspaceTilePatterns on KoiWorkspaceTile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _KoiWorkspaceTile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _KoiWorkspaceTile() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _KoiWorkspaceTile value)  $default,){
final _that = this;
switch (_that) {
case _KoiWorkspaceTile():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _KoiWorkspaceTile value)?  $default,){
final _that = this;
switch (_that) {
case _KoiWorkspaceTile() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String title,  String description,  String category,  bool highlighted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _KoiWorkspaceTile() when $default != null:
return $default(_that.title,_that.description,_that.category,_that.highlighted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String title,  String description,  String category,  bool highlighted)  $default,) {final _that = this;
switch (_that) {
case _KoiWorkspaceTile():
return $default(_that.title,_that.description,_that.category,_that.highlighted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String title,  String description,  String category,  bool highlighted)?  $default,) {final _that = this;
switch (_that) {
case _KoiWorkspaceTile() when $default != null:
return $default(_that.title,_that.description,_that.category,_that.highlighted);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _KoiWorkspaceTile implements KoiWorkspaceTile {
  const _KoiWorkspaceTile({required this.title, required this.description, required this.category, this.highlighted = false});
  factory _KoiWorkspaceTile.fromJson(Map<String, dynamic> json) => _$KoiWorkspaceTileFromJson(json);

@override final  String title;
@override final  String description;
@override final  String category;
@override@JsonKey() final  bool highlighted;

/// Create a copy of KoiWorkspaceTile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$KoiWorkspaceTileCopyWith<_KoiWorkspaceTile> get copyWith => __$KoiWorkspaceTileCopyWithImpl<_KoiWorkspaceTile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$KoiWorkspaceTileToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _KoiWorkspaceTile&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.category, category) || other.category == category)&&(identical(other.highlighted, highlighted) || other.highlighted == highlighted));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,title,description,category,highlighted);

@override
String toString() {
  return 'KoiWorkspaceTile(title: $title, description: $description, category: $category, highlighted: $highlighted)';
}


}

/// @nodoc
abstract mixin class _$KoiWorkspaceTileCopyWith<$Res> implements $KoiWorkspaceTileCopyWith<$Res> {
  factory _$KoiWorkspaceTileCopyWith(_KoiWorkspaceTile value, $Res Function(_KoiWorkspaceTile) _then) = __$KoiWorkspaceTileCopyWithImpl;
@override @useResult
$Res call({
 String title, String description, String category, bool highlighted
});




}
/// @nodoc
class __$KoiWorkspaceTileCopyWithImpl<$Res>
    implements _$KoiWorkspaceTileCopyWith<$Res> {
  __$KoiWorkspaceTileCopyWithImpl(this._self, this._then);

  final _KoiWorkspaceTile _self;
  final $Res Function(_KoiWorkspaceTile) _then;

/// Create a copy of KoiWorkspaceTile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? title = null,Object? description = null,Object? category = null,Object? highlighted = null,}) {
  return _then(_KoiWorkspaceTile(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,highlighted: null == highlighted ? _self.highlighted : highlighted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
