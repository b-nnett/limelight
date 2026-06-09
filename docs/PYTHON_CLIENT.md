# Python Client

The Python client is a small dependency-free wrapper around the local Limelight HTTP API. It uses the Python standard library only.

## Location

```text
clients/python/spotlight_index_client.py
```

Import it from this repository:

```python
from spotlight_index_client import SpotlightIndexClient
```

If you are running code from outside `clients/python`, add that directory to `PYTHONPATH` or vendor the single client file into your project.

## Create A Client

```python
from spotlight_index_client import SpotlightIndexClient

client = SpotlightIndexClient()
```

With a custom base URL:

```python
client = SpotlightIndexClient(base_url="http://127.0.0.1:8765")
```

With HTTP auth:

```python
client = SpotlightIndexClient(auth_token="local-token")
```

## Search

Use `search()` when you only need results:

```python
results = client.search(
    "passport",
    sources=["photos"],
    types=["image"],
    limit=5,
)

for result in results:
    print(result.source, result.title, result.path)
```

Use `search_response()` when you also need provider status, count, and limit metadata:

```python
response = client.search_response("passport", sources=["photos"], limit=5)

print(response.count)
for provider in response.providers:
    print(provider.source, provider.status, provider.count, provider.error)
```

Search options:

- `sources`: provider names such as `files`, `photos`, `mail`, `messages`, `notes`, or `safari`
- `types`: filters such as `application`, `document`, `image`, `audio`, `video`, `folder`, `archive`, or `source`
- `only_in`: absolute paths for scoped file search
- `limit`: maximum result count

Search results expose normalized fields:

```python
result.id
result.source
result.entity_type
result.title
result.subtitle
result.path
result.url
result.content_type
result.created_at
result.modified_at
result.start_at
result.end_at
result.authors
result.size_bytes
result.metadata
```

## Provider And Schema Methods

```python
client.health()
client.providers()
client.schema()
client.capabilities()
```

`providers()` is useful before search because protected providers can require Full Disk Access or framework permissions.

## Permissions

Request permission prompts or setup guidance:

```python
client.request_permissions(["contacts", "calendar", "reminders", "mail", "messages", "notes", "safari"])
```

Contacts, Calendar, and Reminders can trigger framework permission prompts. Mail, Messages, Notes, and Safari return Full Disk Access setup instructions.

## Item Lookup

Fetch Spotlight metadata for an absolute path:

```python
item = client.item("/Applications/Safari.app")
print(item["item"]["metadata"])
```

Load a provider-backed Notes item and open it locally:

```python
note = client.item(source="notes", id="NOTE-ID")
print(note["item"]["metadata"]["body"])
client.open_item(source="notes", id="NOTE-ID")
```

## Photos Thumbnails

Fetch thumbnail bytes by Photos asset id:

```python
thumbnail = client.photo_thumbnail("PHOTOS-ASSET-UUID")
with open("thumbnail.jpg", "wb") as file:
    file.write(thumbnail)
```

The server also accepts `uuid`:

```python
thumbnail = client.photo_thumbnail_by_uuid("PHOTOS-ASSET-UUID")
```

## Deep Search

Run multiple query terms and optional regex filters:

```python
response = client.deep_search(
    ["passport", "id"],
    regexes=[r"[A-Z0-9]{8,}"],
    sources=["photos"],
    limit_per_query=20,
    limit=10,
)
```

## OCR

OCR a local image path:

```python
response = client.ocr(
    path="/Users/me/Desktop/image.png",
    recognition_level="accurate",
    languages=["en-US"],
    include_text=True,
)

print(response["text"])
```

OCR a Photos asset:

```python
response = client.ocr(photo_uuid="PHOTOS-ASSET-UUID")
```

## Entity Extraction

Extract entities from supplied text:

```python
response = client.extract(
    ["passport_number"],
    text="Passport number is 123456789.",
    include_context=True,
)
```

Extract from search results with OCR:

```python
response = client.extract(
    ["passport_number"],
    search={
        "queries": ["passport"],
        "sources": ["photos"],
        "limit": 50,
    },
    ocr={
        "enabled": True,
        "maxItems": 12,
        "recognitionLevel": "accurate",
    },
    save_to="~/Documents/passport-number.txt",
)
```

## Errors

HTTP errors raise `SpotlightIndexError` with the status code and response body in the message:

```python
from spotlight_index_client import SpotlightIndexError

try:
    client.providers()
except SpotlightIndexError as error:
    print(error)
```

## Tests

Run the Python SDK tests from the repository root:

```sh
python3 -m unittest discover -s clients/python/tests
```

The tests mock HTTP calls and do not require a running Limelight service.
