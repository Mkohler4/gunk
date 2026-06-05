CREATE TABLE gunk_embeddings (
  gunk_id INTEGER PRIMARY KEY REFERENCES gunks(id) ON DELETE CASCADE,
  vector BLOB NOT NULL,
  dim INTEGER NOT NULL CHECK (dim > 0),
  model TEXT NOT NULL
);

CREATE TABLE gunk_clusters (
  member_gunk_id INTEGER PRIMARY KEY REFERENCES gunks(id) ON DELETE CASCADE,
  canonical_gunk_id INTEGER NOT NULL REFERENCES gunks(id) ON DELETE CASCADE,
  similarity REAL NOT NULL CHECK (similarity >= 0 AND similarity <= 1)
);

CREATE INDEX gunk_clusters_canonical_idx
ON gunk_clusters(canonical_gunk_id);
