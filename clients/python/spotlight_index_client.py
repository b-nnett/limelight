from __future__ import annotations

from dataclasses import dataclass
import json
from typing import Any
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


@dataclass(frozen=True)
class SearchResult:
    id: str
    source: str
    entity_type: str
    title: str
    subtitle: str | None
    path: str | None
    url: str | None
    content_type: str | None
    created_at: str | None
    modified_at: str | None
    start_at: str | None
    end_at: str | None
    authors: list[str] | None
    size_bytes: int | None
    metadata: dict[str, Any]

    @classmethod
    def from_json(cls, value: dict[str, Any]) -> "SearchResult":
        return cls(
            id=value["id"],
            source=value["source"],
            entity_type=value["entityType"],
            title=value["title"],
            subtitle=value.get("subtitle"),
            path=value.get("path"),
            url=value.get("url"),
            content_type=value.get("contentType"),
            created_at=value.get("createdAt"),
            modified_at=value.get("modifiedAt"),
            start_at=value.get("startAt"),
            end_at=value.get("endAt"),
            authors=value.get("authors"),
            size_bytes=value.get("sizeBytes"),
            metadata=value.get("metadata", {}),
        )


@dataclass(frozen=True)
class ProviderSearchStatus:
    source: str
    status: str
    count: int
    error: str | None

    @classmethod
    def from_json(cls, value: dict[str, Any]) -> "ProviderSearchStatus":
        return cls(
            source=value["source"],
            status=value["status"],
            count=value["count"],
            error=value.get("error"),
        )


@dataclass(frozen=True)
class SearchResponse:
    query: str
    count: int
    limit: int
    results: list[SearchResult]
    providers: list[ProviderSearchStatus]

    @classmethod
    def from_json(cls, value: dict[str, Any]) -> "SearchResponse":
        return cls(
            query=value["query"],
            count=value["count"],
            limit=value["limit"],
            results=[SearchResult.from_json(item) for item in value.get("results", [])],
            providers=[ProviderSearchStatus.from_json(item) for item in value.get("providers", [])],
        )


class SpotlightIndexError(RuntimeError):
    pass


class SpotlightIndexClient:
    def __init__(self, base_url: str = "http://127.0.0.1:8765", auth_token: str | None = None) -> None:
        self.base_url = base_url.rstrip("/")
        self.auth_token = auth_token

    def health(self) -> dict[str, Any]:
        return self._request("GET", "/health")

    def providers(self) -> dict[str, Any]:
        return self._request("GET", "/v1/providers")

    def schema(self) -> dict[str, Any]:
        return self._request("GET", "/v1/schema")

    def capabilities(self) -> dict[str, Any]:
        return self._request("GET", "/v1/capabilities")

    def request_permissions(self, sources: list[str] | None = None) -> dict[str, Any]:
        payload: dict[str, Any] = {}
        if sources is not None:
            payload["sources"] = sources
        return self._request("POST", "/v1/permissions/request", payload)

    def photo_thumbnail(self, asset_id: str) -> bytes:
        request = Request(f"{self.base_url}/v1/photos/thumbnail?{urlencode({'id': asset_id})}", method="GET")
        if self.auth_token:
            request.add_header("Authorization", f"Bearer {self.auth_token}")
        try:
            with urlopen(request, timeout=30) as response:
                return response.read()
        except HTTPError as error:
            body = error.read().decode("utf-8")
            raise SpotlightIndexError(f"{error.code}: {body}") from error

    def photo_thumbnail_by_uuid(self, uuid: str) -> bytes:
        request = Request(f"{self.base_url}/v1/photos/thumbnail?{urlencode({'uuid': uuid})}", method="GET")
        if self.auth_token:
            request.add_header("Authorization", f"Bearer {self.auth_token}")
        try:
            with urlopen(request, timeout=30) as response:
                return response.read()
        except HTTPError as error:
            body = error.read().decode("utf-8")
            raise SpotlightIndexError(f"{error.code}: {body}") from error

    def item(self, path: str | None = None, *, source: str | None = None, id: str | None = None) -> dict[str, Any]:
        params: dict[str, str] = {}
        if path is not None:
            params["path"] = path
        if source is not None:
            params["source"] = source
        if id is not None:
            params["id"] = id
        return self._request("GET", f"/v1/item?{urlencode(params)}")

    def open_item(
        self,
        path: str | None = None,
        *,
        source: str | None = None,
        id: str | None = None,
        url: str | None = None,
    ) -> dict[str, Any]:
        payload: dict[str, str] = {}
        if path is not None:
            payload["path"] = path
        if source is not None:
            payload["source"] = source
        if id is not None:
            payload["id"] = id
        if url is not None:
            payload["url"] = url
        return self._request("POST", "/v1/open", payload)

    def search(
        self,
        query: str,
        *,
        sources: list[str] | None = None,
        types: list[str] | None = None,
        only_in: list[str] | None = None,
        limit: int | None = None,
    ) -> list[SearchResult]:
        return self.search_response(
            query,
            sources=sources,
            types=types,
            only_in=only_in,
            limit=limit,
        ).results

    def search_response(
        self,
        query: str,
        *,
        sources: list[str] | None = None,
        types: list[str] | None = None,
        only_in: list[str] | None = None,
        limit: int | None = None,
    ) -> SearchResponse:
        payload: dict[str, Any] = {"query": query}
        if sources is not None:
            payload["sources"] = sources
        if types is not None:
            payload["types"] = types
        if only_in is not None:
            payload["onlyIn"] = only_in
        if limit is not None:
            payload["limit"] = limit

        response = self._request("POST", "/v1/search", payload)
        return SearchResponse.from_json(response)

    def deep_search(
        self,
        queries: list[str],
        *,
        regexes: list[str] | None = None,
        sources: list[str] | None = None,
        types: list[str] | None = None,
        only_in: list[str] | None = None,
        limit_per_query: int | None = None,
        limit: int | None = None,
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {"queries": queries}
        if regexes is not None:
            payload["regexes"] = regexes
        if sources is not None:
            payload["sources"] = sources
        if types is not None:
            payload["types"] = types
        if only_in is not None:
            payload["onlyIn"] = only_in
        if limit_per_query is not None:
            payload["limitPerQuery"] = limit_per_query
        if limit is not None:
            payload["limit"] = limit
        return self._request("POST", "/v1/deep-search", payload)

    def ocr(
        self,
        *,
        path: str | None = None,
        photo_uuid: str | None = None,
        recognition_level: str | None = None,
        languages: list[str] | None = None,
        include_text: bool = True,
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {"includeText": include_text}
        if path is not None:
            payload["path"] = path
        if photo_uuid is not None:
            payload["photoUUID"] = photo_uuid
        if recognition_level is not None:
            payload["recognitionLevel"] = recognition_level
        if languages is not None:
            payload["languages"] = languages
        return self._request("POST", "/v1/ocr", payload)

    def extract(
        self,
        entity_types: list[str],
        *,
        text: str | None = None,
        path: str | None = None,
        photo_uuid: str | None = None,
        search: dict[str, Any] | None = None,
        ocr: dict[str, Any] | None = None,
        save_to: str | None = None,
        include_context: bool | None = None,
        include_ocr_text: bool | None = None,
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {"entityTypes": entity_types}
        if text is not None:
            payload["text"] = text
        if path is not None:
            payload["path"] = path
        if photo_uuid is not None:
            payload["photoUUID"] = photo_uuid
        if search is not None:
            payload["search"] = search
        if ocr is not None:
            payload["ocr"] = ocr
        if save_to is not None:
            payload["saveTo"] = save_to
        if include_context is not None:
            payload["includeContext"] = include_context
        if include_ocr_text is not None:
            payload["includeOCRText"] = include_ocr_text
        return self._request("POST", "/v1/extract", payload)

    def _request(self, method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
        data = None if payload is None else json.dumps(payload).encode("utf-8")
        request = Request(f"{self.base_url}{path}", data=data, method=method)
        request.add_header("Content-Type", "application/json")
        if self.auth_token:
            request.add_header("Authorization", f"Bearer {self.auth_token}")

        try:
            with urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode("utf-8"))
        except HTTPError as error:
            body = error.read().decode("utf-8")
            raise SpotlightIndexError(f"{error.code}: {body}") from error
