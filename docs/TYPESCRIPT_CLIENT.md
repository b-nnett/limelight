# TypeScript Client

The TypeScript client is a typed wrapper around the local Limelight HTTP API. It uses global `fetch`, so it works in Node 18+ and same-origin browser contexts without runtime dependencies. Cross-origin browser calls to `127.0.0.1:8765` are not supported unless the server is fronted by an origin that handles CORS.

## Location

```text
clients/typescript
```

Build it from this repository:

```sh
cd clients/typescript
npm ci
npm run build
```

Import it:

```ts
import { LimelightClient } from "@limelight/client";
```

## Create A Client

```ts
const client = new LimelightClient({ authToken: process.env.LIMELIGHT_AUTH_TOKEN });
```

With a custom base URL:

```ts
const client = new LimelightClient({ baseUrl: "http://127.0.0.1:8765" });
```

With HTTP auth from an installed Limelight app:

```ts
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const authToken = readFileSync(join(homedir(), "Library/Application Support/Limelight/auth-token"), "utf8").trim();
const client = new LimelightClient({ authToken });
```

With an explicit `fetch` implementation:

```ts
const client = new LimelightClient({ fetch: customFetch });
```

## Search

Use `search()` when you only need results:

```ts
const results = await client.search({
  query: "passport",
  sources: ["photos"],
  types: ["image"],
  limit: 5,
});

for (const result of results) {
  console.log(result.source, result.title, result.path);
}
```

Use `searchResponse()` when you also need provider status, count, and limit metadata:

```ts
const response = await client.searchResponse({
  query: "passport",
  sources: ["photos"],
  limit: 5,
});

console.log(response.count);
for (const provider of response.providers) {
  console.log(provider.source, provider.status, provider.count, provider.error);
}
```

`search()` and `searchResponse()` also accept a bare query string:

```ts
const results = await client.search("passport");
```

Search options:

- `sources`: provider names such as `files`, `photos`, `mail`, `messages`, `notes`, or `safari`
- `types`: filters such as `application`, `document`, `image`, `audio`, `video`, `folder`, `archive`, or `source`
- `onlyIn`: absolute paths for scoped file search
- `limit`: maximum result count

Search results expose normalized fields:

```ts
result.id;
result.source;
result.entityType;
result.title;
result.subtitle;
result.path;
result.url;
result.contentType;
result.createdAt;
result.modifiedAt;
result.startAt;
result.endAt;
result.authors;
result.sizeBytes;
result.metadata;
```

## Provider And Schema Methods

```ts
await client.health();
await client.providers();
await client.schema();
await client.capabilities();
```

`providers()` is useful before search because protected providers can require Full Disk Access or framework permissions.

## Permissions

Request permission prompts or setup guidance:

```ts
await client.requestPermissions(["contacts", "calendar", "reminders", "photos", "mail", "messages", "notes", "safari"]);
```

Contacts, Calendar, and Reminders can trigger framework permission prompts. Photos, Mail, Messages, Notes, and Safari return Full Disk Access setup instructions.

## Item Lookup

Fetch Spotlight metadata for an absolute path:

```ts
const item = await client.item("/Applications/Safari.app");
console.log(item.item.metadata);
```

Load a provider-backed Notes item and open it locally:

```ts
const note = await client.item({ source: "notes", id: "NOTE-ID" });
console.log(note.item.metadata.body);
await client.openItem({ source: "notes", id: "NOTE-ID" });
```

## Photos Thumbnails

Fetch thumbnail bytes by Photos asset id:

```ts
const thumbnail = await client.photoThumbnail("PHOTOS-ASSET-UUID");
```

The server also accepts `uuid`:

```ts
const thumbnail = await client.photoThumbnailByUUID("PHOTOS-ASSET-UUID");
```

In Node, write the thumbnail to disk:

```ts
import { writeFile } from "node:fs/promises";

const thumbnail = await client.photoThumbnail("PHOTOS-ASSET-UUID");
await writeFile("thumbnail.jpg", Buffer.from(thumbnail));
```

## Deep Search

Run multiple query terms and optional regex filters:

```ts
const response = await client.deepSearch({
  queries: ["passport", "id"],
  regexes: ["[A-Z0-9]{8,}"],
  sources: ["photos"],
  limitPerQuery: 20,
  limit: 10,
});
```

## OCR

OCR a local image path:

```ts
const response = await client.ocr({
  path: "/Users/me/Desktop/image.png",
  recognitionLevel: "accurate",
  languages: ["en-US"],
  includeText: true,
});

console.log(response.text);
```

OCR a Photos asset:

```ts
const response = await client.ocr({ photoUUID: "PHOTOS-ASSET-UUID" });
```

## Entity Extraction

Extract entities from supplied text:

```ts
const response = await client.extract({
  entityTypes: ["passport_number"],
  text: "Passport number is 123456789.",
  includeContext: true,
});
```

Extract from search results with OCR:

```ts
const response = await client.extract({
  entityTypes: ["passport_number"],
  search: {
    queries: ["passport"],
    sources: ["photos"],
    limit: 50,
  },
  ocr: {
    enabled: true,
    maxItems: 12,
    recognitionLevel: "accurate",
  },
  saveTo: "~/Documents/passport-number.txt",
});
```

## Errors

HTTP errors throw `LimelightError` with `status` and `body` fields:

```ts
import { LimelightError } from "@limelight/client";

try {
  await client.providers();
} catch (error) {
  if (error instanceof LimelightError) {
    console.log(error.status, error.body);
  }
}
```

## Tests

Run the TypeScript SDK tests from the client directory:

```sh
cd clients/typescript
npm ci
npm test
```

The tests use Node's built-in test runner with a mock `fetch`; they do not require a running Limelight service.
