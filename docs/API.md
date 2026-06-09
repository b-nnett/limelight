# API Reference

Limelight exposes a local HTTP API on `127.0.0.1:8765` by default.

## Endpoints

- `GET /health`
- `GET /v1/schema`
- `GET /v1/providers`
- `GET /v1/capabilities`
- `POST /v1/permissions/request`
- `GET /v1/photos/thumbnail?id=PHOTOS-ASSET-UUID`
- `GET /v1/item?path=/absolute/path`
- `POST /v1/search`
- `POST /v1/deep-search`
- `POST /v1/ocr`
- `POST /v1/extract`

Supported type filters are `application`, `document`, `image`, `audio`, `video`, `folder`, `archive`, and `source`.

## Search

When `sources` is omitted, the service fans out across every registered provider and returns per-provider statuses. Use `sources` to constrain the search to one or more providers.

Search files:

```sh
curl -s http://127.0.0.1:8765/v1/search \
  -H 'Content-Type: application/json' \
  -d '{"query":"Codex","sources":["files"],"types":["application"],"onlyIn":["/Applications"],"limit":5}'
```

Search Photos:

```sh
curl -s http://127.0.0.1:8765/v1/search \
  -H 'Content-Type: application/json' \
  -d '{"query":"bennett","sources":["photos"],"types":["image"],"limit":10}'
```

## Permissions

Request permission prompts or setup guidance:

```sh
curl -s http://127.0.0.1:8765/v1/permissions/request \
  -H 'Content-Type: application/json' \
  -d '{"sources":["contacts","calendar","reminders","mail","notes","safari"]}'
```

Contacts, Calendar, and Reminders can trigger framework permission prompts. Mail, Notes, and Safari return Full Disk Access setup instructions because macOS does not expose a programmatic Full Disk Access prompt.

## Photos Thumbnails

Fetch a Photos thumbnail:

```sh
curl -o thumbnail.jpg 'http://127.0.0.1:8765/v1/photos/thumbnail?id=PHOTOS-ASSET-UUID'
```

The thumbnail endpoint serves only readable derivative files inside the local Photos library.

## Toolbox Endpoints

`/v1/deep-search` runs multiple query terms and optional regex filters, merges duplicate records, and returns match reasons and scores.

`/v1/ocr` extracts text lines and full text from a local image path or Photos asset UUID. Set `includeText:false` to return lines only.

`/v1/extract` extracts typed entities from supplied text, a local image, a Photos asset, or deep-search results. It can OCR matched image results, return the OCR documents used as context, and save the best result to a local `0600` file. Set `includeOCRText:false` to suppress OCR text in the response.

Example: find a passport number from Photos results and save it locally:

```sh
curl -s http://127.0.0.1:8765/v1/extract \
  -H 'Content-Type: application/json' \
  -d '{
    "entityTypes":["passport_number"],
    "search":{"queries":["passport"],"sources":["photos"],"limit":50},
    "ocr":{"enabled":true,"maxItems":12,"recognitionLevel":"accurate"},
    "saveTo":"~/Documents/passport-number.txt"
  }'
```

## Authentication

When auth is enabled, include the bearer token on every endpoint except `/health`:

```sh
curl -H "Authorization: Bearer local-token" http://127.0.0.1:8765/v1/providers
```
