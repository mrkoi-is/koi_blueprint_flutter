import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_failure.freezed.dart';

@freezed
sealed class AppFailure with _$AppFailure {
  const AppFailure._();

  const factory AppFailure.validation({required String message}) =
      ValidationFailure;

  const factory AppFailure.network({required String message}) = NetworkFailure;

  const factory AppFailure.unauthorized({
    @Default('登录态已失效，请重新登录') String message,
  }) = UnauthorizedFailure;

  const factory AppFailure.unknown({
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) = UnknownFailure;

  String get displayMessage => switch (this) {
    ValidationFailure(:final message) => message,
    NetworkFailure(:final message) => message,
    UnauthorizedFailure(:final message) => message,
    UnknownFailure(:final message) => message,
  };
}
