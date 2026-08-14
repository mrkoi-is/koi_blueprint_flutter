import 'package:fpdart/fpdart.dart';
import 'package:koi_core/error/app_failure.dart';

typedef Result<T> = Either<AppFailure, T>;
typedef FutureResult<T> = Future<Result<T>>;

Result<T> success<T>(T value) => Right(value);

Result<T> failure<T>(AppFailure value) => Left(value);
