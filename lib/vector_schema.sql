-- =============================================================================
-- VORTEX-OS - Vector schema (memory/vectors.db)
-- =============================================================================
-- Applied by the engine's Commands::VectorHydrate when sqlite3 is on the
-- PATH. Creates the three tables the engine reads at runtime:
--
--   * vector_embeddings  -- the per-doc embedding rows (one row per chunk)
--   * vector_meta        -- the chunk metadata (source path, offset, etc.)
--   * vector_index_meta  -- the latest model + embedding-dim stamp
--
-- v0.2.3: previously referenced by Commands.cpp but never shipped; the
-- hydrate step would silently no-op if the file was absent. Now ships
-- with the skill so a clean install actually creates a real vector DB.
--
-- All tables are append-only. The engine never UPDATEs or DELETEs rows;
-- it only INSERTs new chunks and bumps the index_meta version stamp.
-- =============================================================================

CREATE TABLE IF NOT EXISTS vector_embeddings (
    chunk_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    embedding   BLOB NOT NULL                  -- float32 little-endian, dim = vector_index_meta.dim
);

CREATE TABLE IF NOT EXISTS vector_meta (
    chunk_id    INTEGER PRIMARY KEY,
    source      TEXT NOT NULL,                  -- e.g. "agents/supervisor.store.json" or "deliverables/<project>/01_script.md"
    offset      INTEGER NOT NULL DEFAULT 0,     -- byte offset into source
    length      INTEGER NOT NULL DEFAULT 0,     -- byte length of the chunk
    hash        TEXT NOT NULL DEFAULT '',       -- sha1 of chunk bytes (for dedupe)
    created_at  INTEGER NOT NULL                -- unix seconds
);

CREATE TABLE IF NOT EXISTS vector_index_meta (
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    model       TEXT NOT NULL,                  -- e.g. "MiniMax-Text-01"
    dim         INTEGER NOT NULL,               -- embedding dim, e.g. 1536
    updated_at  INTEGER NOT NULL                -- unix seconds
);

-- v0.2.3: seed the index_meta with a default row so the engine can read
-- the dim before any embeddings are written. The dim is read from
-- .vortex/model_prices.json; until a real model is configured, the
-- engine treats this row as a hint and falls back to dim=384
-- (sentence-transformers/all-MiniLM-L6-v2 default).
INSERT OR IGNORE INTO vector_index_meta (id, model, dim, updated_at)
VALUES (1, 'default', 384, strftime('%s', 'now'));
