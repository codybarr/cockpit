# Instant interaction targets

On an Apple-silicon Mac with a 50,000-item filename index, Cockpit must be ready within 33 ms at p95 and 50 ms at p99 after its hotkey, return ranked results within 16 ms at p95 and 33 ms at p99 after a query change, and reflect ordinary indexed-folder changes within two seconds at p95. Initial scans may take longer, but they must visibly progress, be cancellable, and never block launcher queries; dropped filesystem events trigger reconciliation.

In plain English: Cockpit should be ready within roughly two video frames almost every time; as the user types, the highlighted match should update within one video frame and never feel laggy; and a changed file should be searchable in about two seconds.
