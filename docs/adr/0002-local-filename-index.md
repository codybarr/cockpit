# Local filename index

Cockpit will maintain a SQLite-backed filename index only for folders the user explicitly selects. Each root is enumerated recursively and then updated from File System Events, with a full reconciliation whenever events are incomplete or a root returns after being unavailable; Cockpit never asks Spotlight for search results or metadata.

## Consequences

The index includes only path and filename-oriented metadata needed to open and rank results, not file contents. Hidden items, package contents, and symlink traversal are excluded by default, which makes the first-release search space predictable and keeps indexing surgical.
