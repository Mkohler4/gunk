INSERT INTO tags (name) VALUES ('mobile')
ON CONFLICT(name) DO NOTHING;
