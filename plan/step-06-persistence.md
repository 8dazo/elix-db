# Step 6: Persistence

**Status:** Done

## Goal

Add **file-based persistence**: on shutdown (or on demand), save collection configs and all points to a file (e.g. `:erlang.term_to_binary/1` or custom format). On application start, load from file if it exists and restore collections and points so that after restart the store is identical.

## Tasks

- [ ] Choose file path: e.g. configurable via application env `data_dir` or a fixed path under project.
- [ ] Serialize: collection configs + per-collection points. Ensure dimension and metric are stored with each collection; vectors and payloads with each point.
- [ ] Implement save: write serialized state to file (e.g. `File.write!/2` with term_to_binary). Trigger on `terminate/2` of the main store GenServer and/or via explicit `persist()` call.
- [ ] Implement load: on init, if file exists, read and deserialize; recreate collections and ETS tables and insert points. If file missing or corrupt, start empty.
- [ ] Ensure no data loss on normal shutdown (save before exit).

## Debug

- Start app, create collection, upsert points. Call persist (or stop app gracefully). Restart app; list collections and search—state should match. Corrupt file or remove file and restart—should start empty.

## Verify

- [ ] Tests: save then load in same process or simulate restart; state equals after load. Empty store saves and loads. Invalid file does not crash app.

## Industry Comparison

| Aspect | Qdrant/Milvus | elix-db (this step) | Notes |
|--------|----------------|---------------------|-------|
| Durability | WAL / object storage | Single file snapshot | Simpler; no WAL yet. |
| Recovery | Replay WAL | Load snapshot | Full snapshot only; incremental later. |

**Efficiency notes:** Snapshot is O(n) and blocks; for large stores consider background save or WAL in future. Document file size vs vector count for benchmarking.
