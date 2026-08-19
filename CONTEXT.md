# Cockpit

Cockpit is a local macOS launcher for quickly opening applications and files without relying on Spotlight indexing.

## Language

**Launcher**:
The keyboard-invoked Cockpit surface that accepts a query and presents executable results.
_Avoid_: search bar, palette

**Launchpad**:
The primary text field in the Launcher where a user enters a query.
_Avoid_: search bar, query field

**Indexed folder**:
A user-selected filesystem location whose filenames Cockpit discovers and maintains locally.
_Avoid_: watched folder, catalog

**Filename index**:
Cockpit’s local record of the paths and filename metadata found beneath indexed folders; it never contains file contents or depends on Spotlight.
_Avoid_: search index, Spotlight database

**File-search prefix**:
The leading apostrophe (`'`) in a launcher query that explicitly switches Cockpit from its default application-and-system search to filename matching.
_Avoid_: file mode toggle

**Application catalog**:
Cockpit’s independently maintained record of launchable macOS application bundles from its fixed application locations; it is separate from the filename index.
_Avoid_: app index, installed-app list

**System action**:
A Cockpit command that changes the Mac session or power state, such as locking, restarting, or shutting down.
_Avoid_: power command
