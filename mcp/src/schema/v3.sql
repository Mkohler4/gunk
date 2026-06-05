CREATE TABLE gunk_embeddings (
  gunk_id INTEGER PRIMARY KEY REFERENCES gunks(id) ON DELETE CASCADE,
  vector BLOB NOT NULL,
  dim INTEGER NOT NULL CHECK (dim > 0),
  model TEXT NOT NULL
);
