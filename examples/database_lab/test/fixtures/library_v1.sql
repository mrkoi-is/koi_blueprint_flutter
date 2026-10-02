PRAGMA user_version = 1;
PRAGMA foreign_keys = ON;
CREATE TABLE library_documents (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL);
CREATE TABLE library_tags (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE);
CREATE TABLE library_document_tags (document_id INTEGER NOT NULL REFERENCES library_documents(id) ON DELETE CASCADE, tag_id INTEGER NOT NULL REFERENCES library_tags(id) ON DELETE CASCADE, PRIMARY KEY (document_id, tag_id));
INSERT INTO library_documents(id, title, body) VALUES (7, '迁移前的资料', '旧正文必须保留'), (11, '第二份资料', '包含逗号和单引号的标签');
INSERT INTO library_tags(id, name) VALUES (2, '资料'), (5, 'tag,with,comma'), (9, 'quote''tag');
INSERT INTO library_document_tags(document_id, tag_id) VALUES (7, 2), (11, 5), (11, 9);
