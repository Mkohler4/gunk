CREATE TABLE tags (
  name TEXT PRIMARY KEY,
  description TEXT NOT NULL
);

CREATE TABLE gunk_tags (
  gunk_id INTEGER NOT NULL REFERENCES gunks(id) ON DELETE CASCADE,
  tag TEXT NOT NULL REFERENCES tags(name) ON DELETE RESTRICT,
  confidence REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  source TEXT NOT NULL CHECK (source IN ('llm', 'manual', 'heuristic')),
  tagged_at INTEGER NOT NULL,
  PRIMARY KEY (gunk_id, tag)
);

INSERT INTO tags (name, description) VALUES
  ('auth', 'Authentication and authorization flows'),
  ('payments', 'Billing, checkout, and payment integrations'),
  ('ui-kit', 'Reusable UI components and design systems'),
  ('scraper', 'Crawlers, scrapers, and data collection jobs'),
  ('dashboard', 'Admin, analytics, and reporting dashboards'),
  ('cli', 'Command-line tools and developer utilities'),
  ('api', 'HTTP APIs, RPC services, and backend routes'),
  ('db-layer', 'Database models, migrations, and persistence code'),
  ('email', 'Email templates, delivery, and notification flows'),
  ('search', 'Search, indexing, ranking, and retrieval code');
