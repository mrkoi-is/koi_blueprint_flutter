/// A nonempty prior format, shared by Native and real browser migration tests.
const workspaceV1Fixture = r'''
{
  "schemaVersion": 1,
  "storageVersion": 7,
  "revision": 42,
  "documents": [{"id":"doc","title":"旧版中文资料","text":"保留正文","revision":4,"savedRevision":3}],
  "assets": [{"id":"asset","name":"旧照片.png","kind":"image","byteLength":3,"storageKey":"kept.png","thumbnailStatus":"none"}],
  "todos": [{"id":"todo","title":"不能丢失的事项","completed":true}],
  "jobs": [
    {"id":"done","kind":"importFiles","name":"旧导入","status":"succeeded","processedBytes":3,"totalBytes":3,"importKind":"media"},
    {"id":"running","kind":"thumbnail","name":"未完成缩略图","status":"running","assetId":"asset"},
    {"id":"failed","kind":"importFiles","name":"可重试导入","status":"failed","importKind":"text","error":"磁盘已满"}
  ],
  "preferences": {"themeMode":"dark","density":"compact","navId":"tasks","sidebarWidth":312,"detailsWidth":298,"selectedDocumentId":"doc","selectedAssetId":"asset"}
}
''';
