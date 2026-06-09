from __future__ import annotations

import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from spotlight_index_client import (  # noqa: E402
    SearchResponse,
    SpotlightIndexClient,
    SpotlightIndexError,
)


class MockHTTPResponse:
    def __init__(self, body: bytes) -> None:
        self.body = body

    def __enter__(self) -> "MockHTTPResponse":
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def read(self) -> bytes:
        return self.body

    def close(self) -> None:
        return None


class SpotlightIndexClientTests(unittest.TestCase):
    def capture_request(self, body: dict | bytes = None):
        captured = {}

        def fake_urlopen(request, timeout):
            captured["url"] = request.full_url
            captured["method"] = request.get_method()
            captured["body"] = None if request.data is None else json.loads(request.data.decode("utf-8"))
            captured["authorization"] = request.get_header("Authorization")
            captured["content_type"] = request.get_header("Content-type")
            captured["timeout"] = timeout
            if isinstance(body, bytes):
                return MockHTTPResponse(body)
            return MockHTTPResponse(json.dumps(body if body is not None else {}).encode("utf-8"))

        return captured, fake_urlopen

    def test_search_response_sends_payload_and_maps_results(self) -> None:
        captured = {}

        def fake_urlopen(request, timeout):
            captured["url"] = request.full_url
            captured["method"] = request.get_method()
            captured["body"] = json.loads(request.data.decode("utf-8"))
            captured["authorization"] = request.get_header("Authorization")
            return MockHTTPResponse(
                json.dumps(
                    {
                        "query": "passport",
                        "count": 1,
                        "limit": 5,
                        "results": [
                            {
                                "id": "photo-1",
                                "source": "photos",
                                "entityType": "image",
                                "title": "Passport",
                                "subtitle": "Photos",
                                "path": "/tmp/passport.jpg",
                                "url": None,
                                "contentType": "public.jpeg",
                                "createdAt": "2026-01-01T00:00:00Z",
                                "modifiedAt": None,
                                "startAt": None,
                                "endAt": None,
                                "authors": ["Bennett"],
                                "sizeBytes": 123,
                                "metadata": {"mediaKind": "image"},
                            }
                        ],
                        "providers": [{"source": "photos", "status": "ok", "count": 1, "error": None}],
                    }
                ).encode("utf-8")
            )

        client = SpotlightIndexClient(auth_token="local-token")
        with patch("spotlight_index_client.urlopen", fake_urlopen):
            response = client.search_response(
                "passport",
                sources=["photos"],
                types=["image"],
                only_in=["/Users/bennett/Pictures"],
                limit=5,
            )

        self.assertIsInstance(response, SearchResponse)
        self.assertEqual(captured["url"], "http://127.0.0.1:8765/v1/search")
        self.assertEqual(captured["method"], "POST")
        self.assertEqual(captured["authorization"], "Bearer local-token")
        self.assertEqual(
            captured["body"],
            {
                "query": "passport",
                "sources": ["photos"],
                "types": ["image"],
                "onlyIn": ["/Users/bennett/Pictures"],
                "limit": 5,
            },
        )
        self.assertEqual(response.count, 1)
        self.assertEqual(response.results[0].entity_type, "image")
        self.assertEqual(response.results[0].subtitle, "Photos")
        self.assertEqual(response.results[0].path, "/tmp/passport.jpg")
        self.assertIsNone(response.results[0].url)
        self.assertEqual(response.results[0].content_type, "public.jpeg")
        self.assertEqual(response.results[0].created_at, "2026-01-01T00:00:00Z")
        self.assertIsNone(response.results[0].modified_at)
        self.assertIsNone(response.results[0].start_at)
        self.assertIsNone(response.results[0].end_at)
        self.assertEqual(response.results[0].authors, ["Bennett"])
        self.assertEqual(response.results[0].size_bytes, 123)
        self.assertEqual(response.results[0].metadata, {"mediaKind": "image"})
        self.assertEqual(response.providers[0].status, "ok")

    def test_search_keeps_list_return_for_backward_compatibility(self) -> None:
        def fake_urlopen(request, timeout):
            return MockHTTPResponse(
                json.dumps(
                    {
                        "query": "notes",
                        "count": 1,
                        "limit": 10,
                        "results": [
                            {
                                "id": "note-1",
                                "source": "notes",
                                "entityType": "note",
                                "title": "A note",
                                "metadata": {},
                            }
                        ],
                        "providers": [{"source": "notes", "status": "ok", "count": 1, "error": None}],
                    }
                ).encode("utf-8")
            )

        client = SpotlightIndexClient()
        with patch("spotlight_index_client.urlopen", fake_urlopen):
            results = client.search("notes")

        self.assertEqual(len(results), 1)
        self.assertEqual(results[0].title, "A note")

    def test_ocr_includes_languages_and_include_text(self) -> None:
        captured = {}

        def fake_urlopen(request, timeout):
            captured["body"] = json.loads(request.data.decode("utf-8"))
            return MockHTTPResponse(
                json.dumps(
                    {
                        "sourcePath": "/tmp/image.png",
                        "photoUUID": None,
                        "text": None,
                        "lines": [{"text": "hello", "confidence": 0.95}],
                    }
                ).encode("utf-8")
            )

        client = SpotlightIndexClient()
        with patch("spotlight_index_client.urlopen", fake_urlopen):
            response = client.ocr(path="/tmp/image.png", languages=["en-US"], include_text=False)

        self.assertEqual(captured["body"], {"includeText": False, "path": "/tmp/image.png", "languages": ["en-US"]})
        self.assertEqual(response["lines"][0]["text"], "hello")

    def test_ocr_photo_uuid_and_recognition_level_payload(self) -> None:
        captured, fake_urlopen = self.capture_request(
            {
                "sourcePath": "/photos/asset",
                "photoUUID": "asset-1",
                "text": "hello",
                "lines": [{"text": "hello", "confidence": 0.95}],
            }
        )

        client = SpotlightIndexClient()
        with patch("spotlight_index_client.urlopen", fake_urlopen):
            response = client.ocr(photo_uuid="asset-1", recognition_level="accurate", languages=["en-US"])

        self.assertEqual(
            captured["body"],
            {
                "includeText": True,
                "photoUUID": "asset-1",
                "recognitionLevel": "accurate",
                "languages": ["en-US"],
            },
        )
        self.assertEqual(response["text"], "hello")

    def test_thumbnail_by_uuid_uses_uuid_query_parameter(self) -> None:
        captured = {}

        def fake_urlopen(request, timeout):
            captured["url"] = request.full_url
            return MockHTTPResponse(b"thumbnail-bytes")

        client = SpotlightIndexClient(base_url="http://localhost:9999/")
        with patch("spotlight_index_client.urlopen", fake_urlopen):
            body = client.photo_thumbnail_by_uuid("abc 123")

        self.assertEqual(captured["url"], "http://localhost:9999/v1/photos/thumbnail?uuid=abc+123")
        self.assertEqual(body, b"thumbnail-bytes")

    def test_thumbnail_by_id_uses_id_query_parameter_and_auth(self) -> None:
        captured, fake_urlopen = self.capture_request(b"\x00\xffthumbnail")

        client = SpotlightIndexClient(base_url="http://localhost:9999///", auth_token="local-token")
        with patch("spotlight_index_client.urlopen", fake_urlopen):
            body = client.photo_thumbnail("abc & 123?")

        self.assertEqual(captured["url"], "http://localhost:9999/v1/photos/thumbnail?id=abc+%26+123%3F")
        self.assertEqual(captured["method"], "GET")
        self.assertEqual(captured["authorization"], "Bearer local-token")
        self.assertEqual(body, b"\x00\xffthumbnail")

    def test_http_error_raises_client_error_with_response_body(self) -> None:
        def fake_urlopen(request, timeout):
            raise HTTPError(
                url=request.full_url,
                code=401,
                msg="Unauthorized",
                hdrs={},
                fp=MockHTTPResponse(b'{"error":"unauthorized"}'),
            )

        client = SpotlightIndexClient()
        with patch("spotlight_index_client.urlopen", fake_urlopen):
            with self.assertRaises(SpotlightIndexError) as context:
                client.providers()

        self.assertEqual(str(context.exception), '401: {"error":"unauthorized"}')

    def test_thumbnail_http_error_raises_client_error_with_plain_text_body(self) -> None:
        def fake_urlopen(request, timeout):
            raise HTTPError(
                url=request.full_url,
                code=500,
                msg="Internal Server Error",
                hdrs={},
                fp=MockHTTPResponse(b"internal error"),
            )

        client = SpotlightIndexClient()
        with patch("spotlight_index_client.urlopen", fake_urlopen):
            with self.assertRaises(SpotlightIndexError) as context:
                client.photo_thumbnail("asset-1")

        self.assertEqual(str(context.exception), "500: internal error")

    def test_simple_endpoint_contracts(self) -> None:
        cases = [
            ("health", lambda client: client.health(), "GET", "/health", None, {"status": "ok"}),
            ("providers", lambda client: client.providers(), "GET", "/v1/providers", None, {"providers": []}),
            ("schema", lambda client: client.schema(), "GET", "/v1/schema", None, {"supportedSources": []}),
            ("capabilities", lambda client: client.capabilities(), "GET", "/v1/capabilities", None, {"sources": []}),
            (
                "request_permissions",
                lambda client: client.request_permissions(["mail", "notes"]),
                "POST",
                "/v1/permissions/request",
                {"sources": ["mail", "notes"]},
                {"results": []},
            ),
            (
                "item",
                lambda client: client.item("/tmp/a file & more.txt"),
                "GET",
                "/v1/item?path=%2Ftmp%2Fa+file+%26+more.txt",
                None,
                {"item": {"id": "item-1", "path": "/tmp/a file & more.txt", "metadata": {}}},
            ),
        ]

        for name, call, method, path, body, response in cases:
            with self.subTest(name=name):
                captured, fake_urlopen = self.capture_request(response)
                client = SpotlightIndexClient(base_url="http://localhost:9999///", auth_token="local-token")
                with patch("spotlight_index_client.urlopen", fake_urlopen):
                    self.assertEqual(call(client), response)

                self.assertEqual(captured["url"], f"http://localhost:9999{path}")
                self.assertEqual(captured["method"], method)
                self.assertEqual(captured["body"], body)
                self.assertEqual(captured["authorization"], "Bearer local-token")
                self.assertEqual(captured["content_type"], "application/json")
                self.assertEqual(captured["timeout"], 30)

    def test_request_permissions_without_sources_sends_empty_object(self) -> None:
        captured, fake_urlopen = self.capture_request({"results": []})

        client = SpotlightIndexClient()
        with patch("spotlight_index_client.urlopen", fake_urlopen):
            client.request_permissions()

        self.assertEqual(captured["body"], {})

    def test_deep_search_sends_full_payload(self) -> None:
        response_body = {
            "queries": ["passport", "id"],
            "regexes": ["[A-Z0-9]{8,}"],
            "count": 1,
            "limit": 10,
            "results": [
                {
                    "result": {"id": "photo-1", "source": "photos", "entityType": "photo", "title": "Passport", "metadata": {}},
                    "matchedQueries": ["passport"],
                    "matchedRegexes": ["[A-Z0-9]{8,}"],
                    "score": 12,
                }
            ],
            "providers": [{"source": "photos", "status": "ok", "count": 1, "error": None}],
        }
        captured, fake_urlopen = self.capture_request(response_body)

        client = SpotlightIndexClient()
        with patch("spotlight_index_client.urlopen", fake_urlopen):
            response = client.deep_search(
                ["passport", "id"],
                regexes=["[A-Z0-9]{8,}"],
                sources=["photos"],
                types=["image"],
                only_in=["/Users/bennett/Pictures"],
                limit_per_query=20,
                limit=10,
            )

        self.assertEqual(captured["url"], "http://127.0.0.1:8765/v1/deep-search")
        self.assertEqual(
            captured["body"],
            {
                "queries": ["passport", "id"],
                "regexes": ["[A-Z0-9]{8,}"],
                "sources": ["photos"],
                "types": ["image"],
                "onlyIn": ["/Users/bennett/Pictures"],
                "limitPerQuery": 20,
                "limit": 10,
            },
        )
        self.assertEqual(response["results"][0]["matchedQueries"], ["passport"])
        self.assertEqual(response["results"][0]["score"], 12)

    def test_extract_sends_full_payload(self) -> None:
        response_body = {
            "entityTypes": ["passport_number"],
            "count": 1,
            "entities": [
                {
                    "entityType": "passport_number",
                    "value": "123456789",
                    "redactedValue": "123***789",
                    "confidence": 92,
                    "reason": "matched OCR text",
                    "source": {"source": "photos", "entityType": "photo", "title": "Passport", "resultID": "photo-1"},
                    "context": "Passport number is 123456789.",
                }
            ],
            "searchedResults": 3,
            "ocrResults": 1,
            "ocrDocuments": [{"source": {"resultID": "photo-1"}, "text": "Passport number is 123456789.", "lines": []}],
            "savedTo": "/tmp/passport.txt",
        }
        captured, fake_urlopen = self.capture_request(response_body)

        client = SpotlightIndexClient()
        with patch("spotlight_index_client.urlopen", fake_urlopen):
            response = client.extract(
                ["passport_number"],
                text="Passport number is 123456789.",
                path="/tmp/passport.png",
                photo_uuid="photo-1",
                search={"queries": ["passport"], "sources": ["photos"], "limit": 50},
                ocr={"enabled": True, "maxItems": 12, "recognitionLevel": "accurate", "stopOnHighConfidence": True},
                save_to="/tmp/passport.txt",
                include_context=True,
                include_ocr_text=False,
            )

        self.assertEqual(captured["url"], "http://127.0.0.1:8765/v1/extract")
        self.assertEqual(
            captured["body"],
            {
                "entityTypes": ["passport_number"],
                "text": "Passport number is 123456789.",
                "path": "/tmp/passport.png",
                "photoUUID": "photo-1",
                "search": {"queries": ["passport"], "sources": ["photos"], "limit": 50},
                "ocr": {"enabled": True, "maxItems": 12, "recognitionLevel": "accurate", "stopOnHighConfidence": True},
                "saveTo": "/tmp/passport.txt",
                "includeContext": True,
                "includeOCRText": False,
            },
        )
        self.assertEqual(response["entities"][0]["redactedValue"], "123***789")
        self.assertEqual(response["entities"][0]["source"]["resultID"], "photo-1")


if __name__ == "__main__":
    unittest.main()
