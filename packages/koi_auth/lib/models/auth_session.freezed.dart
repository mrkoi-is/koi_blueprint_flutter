// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'auth_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AuthSession<TUser> {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthSession<TUser>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AuthSession<$TUser>()';
}


}

/// @nodoc
class $AuthSessionCopyWith<TUser,$Res>  {
$AuthSessionCopyWith(AuthSession<TUser> _, $Res Function(AuthSession<TUser>) __);
}


/// Adds pattern-matching-related methods to [AuthSession].
extension AuthSessionPatterns<TUser> on AuthSession<TUser> {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AuthUnauthenticated<TUser> value)?  unauthenticated,TResult Function( AuthLoading<TUser> value)?  loading,TResult Function( AuthAuthenticated<TUser> value)?  authenticated,TResult Function( AuthFailureState<TUser> value)?  failure,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AuthUnauthenticated() when unauthenticated != null:
return unauthenticated(_that);case AuthLoading() when loading != null:
return loading(_that);case AuthAuthenticated() when authenticated != null:
return authenticated(_that);case AuthFailureState() when failure != null:
return failure(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AuthUnauthenticated<TUser> value)  unauthenticated,required TResult Function( AuthLoading<TUser> value)  loading,required TResult Function( AuthAuthenticated<TUser> value)  authenticated,required TResult Function( AuthFailureState<TUser> value)  failure,}){
final _that = this;
switch (_that) {
case AuthUnauthenticated():
return unauthenticated(_that);case AuthLoading():
return loading(_that);case AuthAuthenticated():
return authenticated(_that);case AuthFailureState():
return failure(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AuthUnauthenticated<TUser> value)?  unauthenticated,TResult? Function( AuthLoading<TUser> value)?  loading,TResult? Function( AuthAuthenticated<TUser> value)?  authenticated,TResult? Function( AuthFailureState<TUser> value)?  failure,}){
final _that = this;
switch (_that) {
case AuthUnauthenticated() when unauthenticated != null:
return unauthenticated(_that);case AuthLoading() when loading != null:
return loading(_that);case AuthAuthenticated() when authenticated != null:
return authenticated(_that);case AuthFailureState() when failure != null:
return failure(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unauthenticated,TResult Function()?  loading,TResult Function( TUser user,  String token)?  authenticated,TResult Function( String message)?  failure,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AuthUnauthenticated() when unauthenticated != null:
return unauthenticated();case AuthLoading() when loading != null:
return loading();case AuthAuthenticated() when authenticated != null:
return authenticated(_that.user,_that.token);case AuthFailureState() when failure != null:
return failure(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unauthenticated,required TResult Function()  loading,required TResult Function( TUser user,  String token)  authenticated,required TResult Function( String message)  failure,}) {final _that = this;
switch (_that) {
case AuthUnauthenticated():
return unauthenticated();case AuthLoading():
return loading();case AuthAuthenticated():
return authenticated(_that.user,_that.token);case AuthFailureState():
return failure(_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unauthenticated,TResult? Function()?  loading,TResult? Function( TUser user,  String token)?  authenticated,TResult? Function( String message)?  failure,}) {final _that = this;
switch (_that) {
case AuthUnauthenticated() when unauthenticated != null:
return unauthenticated();case AuthLoading() when loading != null:
return loading();case AuthAuthenticated() when authenticated != null:
return authenticated(_that.user,_that.token);case AuthFailureState() when failure != null:
return failure(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class AuthUnauthenticated<TUser> extends AuthSession<TUser> {
  const AuthUnauthenticated(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthUnauthenticated<TUser>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AuthSession<$TUser>.unauthenticated()';
}


}




/// @nodoc


class AuthLoading<TUser> extends AuthSession<TUser> {
  const AuthLoading(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthLoading<TUser>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AuthSession<$TUser>.loading()';
}


}




/// @nodoc


class AuthAuthenticated<TUser> extends AuthSession<TUser> {
  const AuthAuthenticated({required this.user, required this.token}): super._();
  

 final  TUser user;
 final  String token;

/// Create a copy of AuthSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AuthAuthenticatedCopyWith<TUser, AuthAuthenticated<TUser>> get copyWith => _$AuthAuthenticatedCopyWithImpl<TUser, AuthAuthenticated<TUser>>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthAuthenticated<TUser>&&const DeepCollectionEquality().equals(other.user, user)&&(identical(other.token, token) || other.token == token));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(user),token);

@override
String toString() {
  return 'AuthSession<$TUser>.authenticated(user: $user, token: $token)';
}


}

/// @nodoc
abstract mixin class $AuthAuthenticatedCopyWith<TUser,$Res> implements $AuthSessionCopyWith<TUser, $Res> {
  factory $AuthAuthenticatedCopyWith(AuthAuthenticated<TUser> value, $Res Function(AuthAuthenticated<TUser>) _then) = _$AuthAuthenticatedCopyWithImpl;
@useResult
$Res call({
 TUser user, String token
});




}
/// @nodoc
class _$AuthAuthenticatedCopyWithImpl<TUser,$Res>
    implements $AuthAuthenticatedCopyWith<TUser, $Res> {
  _$AuthAuthenticatedCopyWithImpl(this._self, this._then);

  final AuthAuthenticated<TUser> _self;
  final $Res Function(AuthAuthenticated<TUser>) _then;

/// Create a copy of AuthSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? user = freezed,Object? token = null,}) {
  return _then(AuthAuthenticated<TUser>(
user: freezed == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as TUser,token: null == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AuthFailureState<TUser> extends AuthSession<TUser> {
  const AuthFailureState({required this.message}): super._();
  

 final  String message;

/// Create a copy of AuthSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AuthFailureStateCopyWith<TUser, AuthFailureState<TUser>> get copyWith => _$AuthFailureStateCopyWithImpl<TUser, AuthFailureState<TUser>>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthFailureState<TUser>&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'AuthSession<$TUser>.failure(message: $message)';
}


}

/// @nodoc
abstract mixin class $AuthFailureStateCopyWith<TUser,$Res> implements $AuthSessionCopyWith<TUser, $Res> {
  factory $AuthFailureStateCopyWith(AuthFailureState<TUser> value, $Res Function(AuthFailureState<TUser>) _then) = _$AuthFailureStateCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$AuthFailureStateCopyWithImpl<TUser,$Res>
    implements $AuthFailureStateCopyWith<TUser, $Res> {
  _$AuthFailureStateCopyWithImpl(this._self, this._then);

  final AuthFailureState<TUser> _self;
  final $Res Function(AuthFailureState<TUser>) _then;

/// Create a copy of AuthSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(AuthFailureState<TUser>(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
