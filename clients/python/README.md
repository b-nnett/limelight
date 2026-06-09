# Limelight Python Client

Small dependency-free client for the local Limelight HTTP API.

Full documentation: [Python Client](../../docs/PYTHON_CLIENT.md).

```python
from spotlight_index_client import SpotlightIndexClient

client = SpotlightIndexClient()
for result in client.search("passport", sources=["photos"], types=["image"], limit=5):
    print(result.source, result.title, result.path)
```

Use `search_response()` when you need provider status, count, and limit metadata:

```python
response = client.search_response("passport", sources=["photos"], limit=5)
print(response.count, response.providers)
```

When HTTP auth is enabled:

```python
client = SpotlightIndexClient(auth_token="local-token")
```

The client also covers provider readiness, schema/capabilities, permission requests, item lookup, Photos thumbnails, deep search, OCR, and entity extraction.

## Tests

```sh
python3 -m unittest discover -s clients/python/tests
```

The tests mock HTTP calls and do not require a running Limelight service.
