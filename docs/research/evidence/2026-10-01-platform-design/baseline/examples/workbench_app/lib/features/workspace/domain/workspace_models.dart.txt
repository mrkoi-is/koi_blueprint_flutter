import 'package:freezed_annotation/freezed_annotation.dart';

part 'workspace_models.freezed.dart';
part 'workspace_models.g.dart';

enum ImportKind { text, media }

enum MediaKind { image, video }

enum ThumbnailStatus { none, generating, ready, failed }

enum JobKind { importFiles, thumbnail }

enum JobStatus {
  queued,
  running,
  cancelling,
  succeeded,
  failed,
  cancelled,
  interrupted,
}

enum WorkspaceThemeMode { system, light, dark }

enum WorkspaceDensity { comfortable, compact }

@freezed
abstract class WorkspaceDocument with _$WorkspaceDocument {
  const WorkspaceDocument._();
  const factory WorkspaceDocument({
    required String id,
    required String title,
    @Default('') String text,
    @Default(0) int revision,
    @Default(0) int savedRevision,
  }) = _WorkspaceDocument;
  factory WorkspaceDocument.fromJson(Map<String, dynamic> json) =>
      _$WorkspaceDocumentFromJson(json);
  bool get dirty => revision != savedRevision;
}

@freezed
abstract class WorkspaceAsset with _$WorkspaceAsset {
  const factory WorkspaceAsset({
    required String id,
    required String name,
    required MediaKind kind,
    required int byteLength,
    required String storageKey,
    String? thumbnailKey,
    @Default(ThumbnailStatus.none) ThumbnailStatus thumbnailStatus,
    String? thumbnailError,
  }) = _WorkspaceAsset;
  factory WorkspaceAsset.fromJson(Map<String, dynamic> json) =>
      _$WorkspaceAssetFromJson(json);
}

@freezed
abstract class WorkspaceTodo with _$WorkspaceTodo {
  const factory WorkspaceTodo({
    required String id,
    required String title,
    @Default(false) bool completed,
  }) = _WorkspaceTodo;
  factory WorkspaceTodo.fromJson(Map<String, dynamic> json) =>
      _$WorkspaceTodoFromJson(json);
}

@freezed
abstract class WorkspaceJob with _$WorkspaceJob {
  const WorkspaceJob._();
  const factory WorkspaceJob({
    required String id,
    required JobKind kind,
    required String name,
    @Default(JobStatus.queued) JobStatus status,
    @Default(0) int processedBytes,
    @Default(true) bool indeterminate,
    int? totalBytes,
    String? assetId,
    ImportKind? importKind,
    String? error,
  }) = _WorkspaceJob;
  factory WorkspaceJob.fromJson(Map<String, dynamic> json) =>
      _$WorkspaceJobFromJson(json);
  bool get terminal => switch (status) {
    JobStatus.succeeded ||
    JobStatus.failed ||
    JobStatus.cancelled ||
    JobStatus.interrupted => true,
    _ => false,
  };
}

@freezed
abstract class WorkspacePreferences with _$WorkspacePreferences {
  const factory WorkspacePreferences({
    @Default(WorkspaceThemeMode.system) WorkspaceThemeMode themeMode,
    @Default(WorkspaceDensity.comfortable) WorkspaceDensity density,
    @Default('text') String navId,
    @Default(280) double sidebarWidth,
    @Default(280) double detailsWidth,
    String? selectedDocumentId,
    String? selectedAssetId,
  }) = _WorkspacePreferences;
  factory WorkspacePreferences.fromJson(Map<String, dynamic> json) =>
      _$WorkspacePreferencesFromJson(json);
}

@freezed
abstract class WorkspaceSnapshot with _$WorkspaceSnapshot {
  const factory WorkspaceSnapshot({
    @Default(1) int schemaVersion,
    @Default(0) int revision,
    @Default(<WorkspaceDocument>[]) List<WorkspaceDocument> documents,
    @Default(<WorkspaceAsset>[]) List<WorkspaceAsset> assets,
    @Default(<WorkspaceTodo>[]) List<WorkspaceTodo> todos,
    @Default(<WorkspaceJob>[]) List<WorkspaceJob> jobs,
    @Default(WorkspacePreferences()) WorkspacePreferences preferences,
  }) = _WorkspaceSnapshot;
  factory WorkspaceSnapshot.fromJson(Map<String, dynamic> json) =>
      _$WorkspaceSnapshotFromJson(json);
}

@freezed
abstract class WorkspaceState with _$WorkspaceState {
  const factory WorkspaceState({
    @Default(WorkspaceSnapshot()) WorkspaceSnapshot snapshot,
    @Default(false) bool initialized,
    @Default(false) bool saving,
    String? error,
  }) = _WorkspaceState;
}

List<WorkspaceDocument> searchDocuments(
  List<WorkspaceDocument> documents,
  String query,
) {
  final needle = query.trim().toLowerCase();
  return List.unmodifiable(
    documents.where(
      (document) =>
          needle.isEmpty ||
          document.title.toLowerCase().contains(needle) ||
          document.text.toLowerCase().contains(needle),
    ),
  );
}
