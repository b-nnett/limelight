# Limelight Capability Matrix

Generated from `http://127.0.0.1:8765/v1/capabilities` for the currently running local service.

Readiness is runtime-dependent: `ready`, `partial`, `needs_permission`, and `missing` reflect this machine, user account, app permissions, local data stores, and signing/entitlement state. They are not universal product-readiness claims.

| Source | Local Runtime Status | Permission | Entity Types | Supported Fields | Limitations |
| --- | --- | --- | --- | --- | --- |
| files | ready | Spotlight indexing; scoped filesystem access for paths being queried. | file | authors, bundleIdentifier, contentType, entityType, id, kMDItemContentType, kMDItemDisplayName, kMDItemFSSize, kMDItemKind, path, source, title | Uses Spotlight file metadata; ranking and content-match explanation are still basic. |
| photos | ready | Readable local Photos library database/search indexes. | photo, video | entityType, height, id, matchReason, mediaKind, path, source, subtitle, title, uuid, width | Uses private Photos SQLite/search indexes; thumbnails are served from local derivatives only when available. |
| contacts | ready | Contacts permission. | contact | birthday, emails, entityType, id, identifier, organization, phones, source, subtitle, title | Requires user permission and may return duplicate local/iCloud contact cards. |
| calendar | ready | Calendar permission; Contacts permission for birthday fallback. | calendar-event, birthday | calendar, endAt, entityType, eventIdentifier, id, location, source, startAt, subtitle, title | Private Calendar SQLite fallback is machine-dependent; EventKit supplies most live results. |
| reminders | ready | Reminders permission or readable local Reminders private store. | reminder | completed, entityType, id, reminderID, source, startAt, title | Uses EventKit when permission is granted; private-store fallback remains schema-dependent. |
| notes | ready | Full Disk Access for Notes private store. | note | body, bodyLength, entityType, id, matchReason, modifiedAt, noteID, notesIdentifier, openURL, source, subtitle, title, url | Search returns snippets; full decoded note bodies are available through item lookup. Rich attributed attachment decoding is still best-effort. |
| mail | ready | Full Disk Access for Mail Envelope Index. | email | authors, createdAt, entityType, flags, id, mailbox, messageID, recipients, rowid, snippet, source, subtitle, title | Mail message file paths and mailbox/account metadata are not fully resolved yet. |
| messages | ready | Full Disk Access for Messages chat.db. | message | authors, chat, createdAt, entityType, guid, handle, id, isFromMe, rowid, service, snippet, source, subtitle, title, url | Reads the local Messages chat database; rich attributed body decoding is best-effort and full conversation export is intentionally not implemented. |
| safari | ready | Full Disk Access for Safari History.db. | safari-history | entityType, historyID, id, modifiedAt, source, subtitle, title, url, visitCount, visitedAt | Only Safari history is implemented; Chrome/Arc history are pending. |
