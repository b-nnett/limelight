# Providers

Limelight is local-first. It binds to loopback by default, does not persist a search cache, and does not expose full document text by default.

## Sources

- `files`: native Spotlight file metadata through `MDQuery` and `MDItem`
- `photos`: Photos library search/person indexes, with local derivative path resolution when available
- `contacts`: Contacts.framework, subject to Contacts permission
- `calendar`: EventKit plus local/private fallback paths and Contacts birthday fallback
- `reminders`: EventKit and local reminders SQLite fallback when accessible
- `notes`: local Notes SQLite/private-store fallback when accessible, with full body loading through `/v1/item`
- `mail`: local Mail envelope SQLite/private-store fallback when accessible
- `messages`: local Messages chat SQLite/private-store fallback when accessible
- `safari`: Safari history SQLite fallback when accessible

## Permissions

Contacts, Calendar, and Reminders use macOS framework permissions where possible.

Mail, Messages, Notes, Safari, and some Calendar/Reminders stores are protected by macOS privacy controls. If the process running Limelight lacks Full Disk Access, those providers return an explicit provider error rather than silently returning zero results.

Mail and Safari also try CoreSpotlight app-entity queries before direct private-store reads. Notes prefers the private store first so results can be loaded later, then falls back to CoreSpotlight if the private store is unavailable. Mail app-entity search is additionally gated by Apple's private `com.apple.corespotlight.search.allow.mail` entitlement, which cannot be made usable with a simple ad-hoc signature.

## Notes Loading

Notes search returns snippets. When the Notes private store is readable, load the full note with:

```sh
curl -s 'http://127.0.0.1:8765/v1/item?source=notes&id=NOTE-ID'
```

`NOTE-ID` can be the search result `id`, `metadata.noteID`, or a Notes deep link containing an `identifier` query parameter. Loaded Notes items include `metadata.body` and, when Apple stores a durable identifier, a `notes://showNote?...` URL that can be passed to `/v1/open`.

## Readiness

Inspect live provider readiness:

```sh
curl -s http://127.0.0.1:8765/v1/providers | jq
```

Provider readiness statuses include `ready`, `partial`, `needs_permission`, and `missing`, with setup hints for protected stores.

The generated [Capability Matrix](CAPABILITY_MATRIX.md) shows live source capability and field support from `/v1/capabilities`.
