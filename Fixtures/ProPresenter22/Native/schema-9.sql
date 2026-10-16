-- ProPresenter 22 beta 369098875, schema 9; schema only, no workspace content.
PRAGMA application_id=1381390163;
PRAGMA user_version=9;
CREATE TABLE workspace_cutover_acknowledgements (
         migration_scope TEXT NOT NULL CHECK(length(migration_scope) > 0),
         migration_version TEXT NOT NULL CHECK(length(migration_version) > 0),
         document_id BLOB NOT NULL CHECK(length(document_id) = 16),
         scope INTEGER NOT NULL CHECK(scope IN (0, 1)),
         canonical_manifest_fingerprint BLOB NOT NULL
             CHECK(length(canonical_manifest_fingerprint) = 32),
         client_state_fingerprint BLOB NOT NULL CHECK(length(client_state_fingerprint) = 32),
         candidate_id BLOB NOT NULL CHECK(length(candidate_id) = 16),
         integrated_snapshot BLOB NOT NULL,
         integrated_snapshot_fingerprint BLOB NOT NULL
             CHECK(length(integrated_snapshot_fingerprint) = 32),
         byte_count INTEGER NOT NULL
             CHECK(byte_count >= 0 AND byte_count = length(integrated_snapshot)),
         recovery_artifact_fingerprint BLOB
             CHECK(recovery_artifact_fingerprint IS NULL OR
                   length(recovery_artifact_fingerprint) = 32),
         recorded_at_ms INTEGER NOT NULL CHECK(recorded_at_ms >= 0),
         acknowledged_at_ms INTEGER CHECK(acknowledged_at_ms >= recorded_at_ms),
         PRIMARY KEY(
             migration_scope, migration_version, document_id, scope,
             canonical_manifest_fingerprint, client_state_fingerprint, candidate_id)
     ) WITHOUT ROWID;
CREATE TABLE workspace_cutover_recovery_artifacts (
         migration_scope TEXT NOT NULL CHECK(length(migration_scope) > 0),
         migration_version TEXT NOT NULL CHECK(length(migration_version) > 0),
         document_id BLOB NOT NULL CHECK(length(document_id) = 16),
         scope INTEGER NOT NULL CHECK(scope IN (0, 1)),
         canonical_manifest_fingerprint BLOB NOT NULL
             CHECK(length(canonical_manifest_fingerprint) = 32),
         client_state_fingerprint BLOB NOT NULL CHECK(length(client_state_fingerprint) = 32),
         artifact BLOB NOT NULL CHECK(length(artifact) > 0),
         artifact_fingerprint BLOB NOT NULL CHECK(length(artifact_fingerprint) = 32),
         recorded_at_ms INTEGER NOT NULL CHECK(recorded_at_ms >= 0),
         PRIMARY KEY(
             migration_scope, migration_version, document_id, scope,
             canonical_manifest_fingerprint, client_state_fingerprint)
     ) WITHOUT ROWID;
CREATE TABLE workspace_metadata (
                 key TEXT PRIMARY KEY,
                 value TEXT NOT NULL
             ) WITHOUT ROWID;
CREATE TABLE workspace_migration_quarantine (
         migration_scope TEXT NOT NULL CHECK(length(migration_scope) > 0),
         migration_version TEXT NOT NULL CHECK(length(migration_version) > 0),
         document_id BLOB NOT NULL CHECK(length(document_id) = 16),
         scope INTEGER NOT NULL CHECK(scope IN (0, 1)),
         source_sha256 BLOB NOT NULL CHECK(length(source_sha256) = 32),
         source_snapshot BLOB NOT NULL,
         reason TEXT NOT NULL CHECK(length(reason) > 0),
         recorded_at_ms INTEGER NOT NULL CHECK(recorded_at_ms >= 0),
         PRIMARY KEY(
             migration_scope, migration_version, document_id, scope, source_sha256)
     ) WITHOUT ROWID;
CREATE TABLE workspace_operation_receipts (
                 operation_id BLOB PRIMARY KEY CHECK(length(operation_id) = 16),
                 operation_kind TEXT NOT NULL CHECK(length(operation_kind) > 0),
                 workspace_generation INTEGER NOT NULL CHECK(workspace_generation >= 0),
                 document_id BLOB NOT NULL CHECK(length(document_id) = 16),
                 scope INTEGER NOT NULL CHECK(scope IN (0, 1)),
                 payload_fingerprint BLOB NOT NULL CHECK(length(payload_fingerprint) = 32),
                 disposition INTEGER NOT NULL CHECK(disposition IN (0, 1)),
                 durable_version_vector BLOB NOT NULL,
                 created_at_ms INTEGER NOT NULL CHECK(created_at_ms >= 0)
             , operation_context_fingerprint BLOB NOT NULL
                 DEFAULT X'0000000000000000000000000000000000000000000000000000000000000000'
                 CHECK(length(operation_context_fingerprint) = 32)) WITHOUT ROWID;
CREATE TABLE workspace_streams (
                 document_id BLOB NOT NULL CHECK(length(document_id) = 16),
                 scope INTEGER NOT NULL CHECK(scope IN (0, 1)),
                 location_type INTEGER NOT NULL CHECK(location_type IN (0, 1)),
                 kind TEXT NOT NULL,
                 core_path TEXT,
                 availability INTEGER NOT NULL CHECK(availability IN (0, 1)),
                 snapshot BLOB,
                 version_vector BLOB,
                 sha256 BLOB CHECK(sha256 IS NULL OR length(sha256) = 32),
                 byte_count INTEGER NOT NULL CHECK(byte_count >= 0),
                 updated_at_ms INTEGER NOT NULL CHECK(updated_at_ms >= 0), last_shared_version_vector BLOB, last_shared_version_vector_absence_reason INTEGER
                     CHECK(last_shared_version_vector_absence_reason IS NULL OR
                           last_shared_version_vector_absence_reason IN (0, 1, 2, 3)), core_path_key TEXT,
                 PRIMARY KEY(document_id, scope),
                 CHECK((location_type = 0 AND core_path IS NULL) OR
                       (location_type = 1 AND scope = 0 AND core_path IS NOT NULL AND length(core_path) > 0)),
                 CHECK((availability = 0 AND snapshot IS NOT NULL AND version_vector IS NOT NULL AND
                        sha256 IS NOT NULL AND byte_count = length(snapshot)) OR
                       (availability = 1 AND scope = 0 AND location_type = 1 AND snapshot IS NULL AND
                        version_vector IS NULL AND sha256 IS NULL AND byte_count = 0))
             );
CREATE UNIQUE INDEX workspace_collection_location
                 ON workspace_streams(kind, core_path_key)
                 WHERE location_type = 1;
CREATE UNIQUE INDEX workspace_intrinsic_location
                 ON workspace_streams(scope, kind)
                 WHERE location_type = 0;
CREATE INDEX workspace_operation_receipts_created_at
                 ON workspace_operation_receipts(created_at_ms);
