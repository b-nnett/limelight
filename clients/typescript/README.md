# Limelight TypeScript Client

TypeScript client for the local Limelight HTTP API. It has no runtime dependencies and uses global `fetch`, available in Node 18+ and same-origin browser contexts.

Full documentation: [TypeScript Client](../../docs/TYPESCRIPT_CLIENT.md).

## Install

From this repository:

```sh
cd clients/typescript
npm ci
npm run build
```

## Usage

```ts
import { LimelightClient } from "@limelight/client";

const client = new LimelightClient({ originatorApp: "Codex" });
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

Use `searchResponse()` when you need provider status, count, and limit metadata:

```ts
const response = await client.searchResponse({
  query: "passport",
  sources: ["photos"],
  limit: 5,
});

console.log(response.count, response.providers);
```

`originatorApp` is sent as `X-Origin` for Limelight's recent-search UI.

The client covers provider readiness, schema/capabilities, permission requests, item lookup, Photos thumbnails, deep search, OCR, and entity extraction.

## Tests

```sh
npm test
```

The tests use Node's built-in test runner with a mock `fetch`; they do not require a running Limelight service.
