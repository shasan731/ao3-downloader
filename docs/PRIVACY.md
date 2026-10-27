# Privacy

ArchiveBind is local-first. It has no telemetry, analytics, advertising, cloud backend, or ArchiveBind account.

## Stored on this Mac

- Downloaded books and user-selected destination folders.
- A local Library database containing source URLs, book metadata, file locations, selections, and failure summaries.
- User-selected cover images copied into app-managed storage.
- Network courtesy timing, including a server-directed cooldown when AO3 sends `Retry-After`.
- Settings for request spacing and public Mature/Explicit warning consent.

The app preserves its original internal storage folder name when updating to the ArchiveBind branding so existing Library records continue to work.

## Sent over the network

ArchiveBind requests only exact-host `https://archiveofourown.org` URLs derived from a URL the user supplies. Requests are globally serialized. Enabling the public content-warning preference adds AO3’s public `view_adult=true` choice; it does not import cookies or browser sessions.

ArchiveBind never asks for or stores an AO3 password. Story contents, cookies, credentials, and sensitive URL queries are not logged. Restricted/login-only works and verification challenges are not bypassed.

## Removing local data

Removing an entry from Library leaves downloaded books untouched. Delete those files separately in Finder. Application settings and Library support files can be removed through macOS only after quitting the app; make a backup first if you want to preserve recombination history.
