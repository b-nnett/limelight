import test from "node:test";
import assert from "node:assert/strict";

import { LimelightClient, LimelightError } from "../src/index.js";

type FetchCall = {
  url: string;
  init: RequestInit;
};

function jsonResponse(value: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(value), {
    status: 200,
    headers: { "Content-Type": "application/json" },
    ...init,
  });
}

function makeFetch(response: Response): { fetch: typeof fetch; calls: FetchCall[] } {
  const calls: FetchCall[] = [];
  const fetchMock = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    calls.push({ url: String(input), init: init ?? {} });
    return response;
  };

  return { fetch: fetchMock as typeof fetch, calls };
}

test("searchResponse sends payload and maps response", async () => {
  const { fetch, calls } = makeFetch(
    jsonResponse({
      query: "passport",
      count: 1,
      limit: 5,
      results: [
        {
          id: "photo-1",
          source: "photos",
          entityType: "image",
          title: "Passport",
          subtitle: "Photos",
          path: "/tmp/passport.jpg",
          url: null,
          contentType: "public.jpeg",
          createdAt: "2026-01-01T00:00:00Z",
          modifiedAt: null,
          startAt: null,
          endAt: null,
          authors: ["Bennett"],
          sizeBytes: 123,
          metadata: { mediaKind: "image" },
        },
      ],
      providers: [{ source: "photos", status: "ok", count: 1, error: null }],
    })
  );

  const client = new LimelightClient({ fetch, authToken: "local-token" });
  const response = await client.searchResponse({
    query: "passport",
    sources: ["photos"],
    types: ["image"],
    onlyIn: ["/Users/bennett/Pictures"],
    limit: 5,
  });

  assert.equal(calls[0].url, "http://127.0.0.1:8765/v1/search");
  assert.equal(calls[0].init.method, "POST");
  assert.equal((calls[0].init.headers as Headers).get("Authorization"), "Bearer local-token");
  assert.deepEqual(JSON.parse(calls[0].init.body as string), {
    query: "passport",
    sources: ["photos"],
    types: ["image"],
    onlyIn: ["/Users/bennett/Pictures"],
    limit: 5,
  });
  assert.equal(response.count, 1);
  assert.equal(response.results[0].entityType, "image");
  assert.equal(response.results[0].subtitle, "Photos");
  assert.equal(response.results[0].path, "/tmp/passport.jpg");
  assert.equal(response.results[0].url, null);
  assert.equal(response.results[0].contentType, "public.jpeg");
  assert.equal(response.results[0].createdAt, "2026-01-01T00:00:00Z");
  assert.equal(response.results[0].modifiedAt, null);
  assert.equal(response.results[0].startAt, null);
  assert.equal(response.results[0].endAt, null);
  assert.deepEqual(response.results[0].authors, ["Bennett"]);
  assert.equal(response.results[0].sizeBytes, 123);
  assert.deepEqual(response.results[0].metadata, { mediaKind: "image" });
  assert.equal(response.providers[0].status, "ok");
});

test("search returns result array for convenience", async () => {
  const { fetch } = makeFetch(
    jsonResponse({
      query: "notes",
      count: 1,
      limit: 10,
      results: [{ id: "note-1", source: "notes", entityType: "note", title: "A note", metadata: {} }],
      providers: [{ source: "notes", status: "ok", count: 1, error: null }],
    })
  );

  const client = new LimelightClient({ fetch });
  const results = await client.search("notes");

  assert.equal(results.length, 1);
  assert.equal(results[0].title, "A note");
});

test("ocr sends languages and includeText", async () => {
  const { fetch, calls } = makeFetch(
    jsonResponse({
      sourcePath: "/tmp/image.png",
      photoUUID: null,
      text: null,
      lines: [{ text: "hello", confidence: 0.95 }],
    })
  );

  const client = new LimelightClient({ fetch });
  const response = await client.ocr({ path: "/tmp/image.png", languages: ["en-US"], includeText: false });

  assert.equal(calls[0].url, "http://127.0.0.1:8765/v1/ocr");
  assert.deepEqual(JSON.parse(calls[0].init.body as string), {
    path: "/tmp/image.png",
    languages: ["en-US"],
    includeText: false,
  });
  assert.equal(response.lines[0].text, "hello");
});

test("ocr sends photoUUID and recognitionLevel", async () => {
  const { fetch, calls } = makeFetch(
    jsonResponse({
      sourcePath: "/photos/asset",
      photoUUID: "asset-1",
      text: "hello",
      lines: [{ text: "hello", confidence: 0.95 }],
    })
  );

  const client = new LimelightClient({ fetch });
  const response = await client.ocr({ photoUUID: "asset-1", recognitionLevel: "accurate", languages: ["en-US"] });

  assert.deepEqual(JSON.parse(calls[0].init.body as string), {
    photoUUID: "asset-1",
    recognitionLevel: "accurate",
    languages: ["en-US"],
  });
  assert.equal(response.text, "hello");
});

test("photoThumbnailByUUID uses uuid query parameter and returns binary body", async () => {
  const bytes = new Uint8Array([1, 2, 3]);
  const { fetch, calls } = makeFetch(new Response(bytes));

  const client = new LimelightClient({ baseUrl: "http://localhost:9999/", fetch });
  const response = await client.photoThumbnailByUUID("abc 123");

  assert.equal(calls[0].url, "http://localhost:9999/v1/photos/thumbnail?uuid=abc+123");
  assert.deepEqual(Array.from(new Uint8Array(response)), [1, 2, 3]);
});

test("photoThumbnail uses id query parameter and includes binary auth", async () => {
  const bytes = new Uint8Array([0, 255, 42]);
  const { fetch, calls } = makeFetch(new Response(bytes));

  const client = new LimelightClient({ baseUrl: "http://localhost:9999///", fetch, authToken: "local-token" });
  const response = await client.photoThumbnail("abc & 123?");

  assert.equal(calls[0].url, "http://localhost:9999/v1/photos/thumbnail?id=abc+%26+123%3F");
  assert.equal(calls[0].init.method, "GET");
  assert.equal((calls[0].init.headers as Headers).get("Authorization"), "Bearer local-token");
  assert.equal((calls[0].init.headers as Headers).get("Accept"), null);
  assert.equal((calls[0].init.headers as Headers).get("Content-Type"), null);
  assert.deepEqual(Array.from(new Uint8Array(response)), [0, 255, 42]);
});

test("non-ok responses throw LimelightError with status and body", async () => {
  const { fetch } = makeFetch(new Response('{"error":"unauthorized"}', { status: 401 }));
  const client = new LimelightClient({ fetch });

  await assert.rejects(client.providers(), (error) => {
    assert.ok(error instanceof LimelightError);
    assert.equal(error.status, 401);
    assert.equal(error.body, '{"error":"unauthorized"}');
    return true;
  });
});

test("binary non-ok responses throw LimelightError with plain text body", async () => {
  const { fetch } = makeFetch(new Response("internal error", { status: 500 }));
  const client = new LimelightClient({ fetch });

  await assert.rejects(client.photoThumbnail("asset-1"), (error) => {
    assert.ok(error instanceof LimelightError);
    assert.equal(error.status, 500);
    assert.equal(error.body, "internal error");
    return true;
  });
});

test("simple endpoint contracts use expected routes and bodies", async () => {
  const cases: Array<{
    name: string;
    run: (client: LimelightClient) => Promise<unknown>;
    method: string;
    path: string;
    body?: unknown;
    response: unknown;
  }> = [
    { name: "health", run: (client) => client.health(), method: "GET", path: "/health", response: { status: "ok" } },
    { name: "providers", run: (client) => client.providers(), method: "GET", path: "/v1/providers", response: { providers: [] } },
    { name: "schema", run: (client) => client.schema(), method: "GET", path: "/v1/schema", response: { supportedSources: [] } },
    {
      name: "capabilities",
      run: (client) => client.capabilities(),
      method: "GET",
      path: "/v1/capabilities",
      response: { generatedAt: "2026-01-01T00:00:00Z", sources: [] },
    },
    {
      name: "requestPermissions",
      run: (client) => client.requestPermissions(["mail", "notes"]),
      method: "POST",
      path: "/v1/permissions/request",
      body: { sources: ["mail", "notes"] },
      response: { results: [] },
    },
    {
      name: "item",
      run: (client) => client.item("/tmp/a file & more.txt"),
      method: "GET",
      path: "/v1/item?path=%2Ftmp%2Fa+file+%26+more.txt",
      response: { item: { id: "item-1", path: "/tmp/a file & more.txt", startAt: null, endAt: null, metadata: {} } },
    },
    {
      name: "provider item",
      run: (client) => client.item({ source: "notes", id: "note-1" }),
      method: "GET",
      path: "/v1/item?source=notes&id=note-1",
      response: { item: { id: "note-1", source: "notes", title: "Note", metadata: { body: "Full note" } } },
    },
    {
      name: "open provider item",
      run: (client) => client.openItem({ source: "notes", id: "note-1" }),
      method: "POST",
      path: "/v1/open",
      body: { source: "notes", id: "note-1" },
      response: { opened: true, target: "notes://showNote?identifier=NOTE-1", item: null },
    },
  ];

  for (const scenario of cases) {
    const { fetch, calls } = makeFetch(jsonResponse(scenario.response));
    const client = new LimelightClient({ baseUrl: "http://localhost:9999///", fetch, authToken: "local-token" });
    const response = await scenario.run(client);

    assert.deepEqual(response, scenario.response, scenario.name);
    assert.equal(calls[0].url, `http://localhost:9999${scenario.path}`, scenario.name);
    assert.equal(calls[0].init.method, scenario.method, scenario.name);
    assert.equal((calls[0].init.headers as Headers).get("Authorization"), "Bearer local-token", scenario.name);
    assert.equal((calls[0].init.headers as Headers).get("Accept"), "application/json", scenario.name);
    if (scenario.body === undefined) {
      assert.equal(calls[0].init.body, undefined, scenario.name);
    } else {
      assert.equal((calls[0].init.headers as Headers).get("Content-Type"), "application/json", scenario.name);
      assert.deepEqual(JSON.parse(calls[0].init.body as string), scenario.body, scenario.name);
    }
  }
});

test("requestPermissions without sources sends an empty object", async () => {
  const { fetch, calls } = makeFetch(jsonResponse({ results: [] }));
  const client = new LimelightClient({ fetch });

  await client.requestPermissions();

  assert.deepEqual(JSON.parse(calls[0].init.body as string), {});
});

test("deepSearch sends full payload and returns nested response", async () => {
  const responseBody = {
    queries: ["passport", "id"],
    regexes: ["[A-Z0-9]{8,}"],
    count: 1,
    limit: 10,
    results: [
      {
        result: { id: "photo-1", source: "photos", entityType: "photo", title: "Passport", metadata: {} },
        matchedQueries: ["passport"],
        matchedRegexes: ["[A-Z0-9]{8,}"],
        score: 12,
      },
    ],
    providers: [{ source: "photos", status: "ok", count: 1, error: null }],
  };
  const { fetch, calls } = makeFetch(jsonResponse(responseBody));
  const client = new LimelightClient({ fetch });

  const response = await client.deepSearch({
    queries: ["passport", "id"],
    regexes: ["[A-Z0-9]{8,}"],
    sources: ["photos"],
    types: ["image"],
    onlyIn: ["/Users/bennett/Pictures"],
    limitPerQuery: 20,
    limit: 10,
  });

  assert.equal(calls[0].url, "http://127.0.0.1:8765/v1/deep-search");
  assert.deepEqual(JSON.parse(calls[0].init.body as string), {
    queries: ["passport", "id"],
    regexes: ["[A-Z0-9]{8,}"],
    sources: ["photos"],
    types: ["image"],
    onlyIn: ["/Users/bennett/Pictures"],
    limitPerQuery: 20,
    limit: 10,
  });
  assert.equal(response.results[0].score, 12);
  assert.deepEqual(response.results[0].matchedQueries, ["passport"]);
});

test("extract sends full payload and returns rich response", async () => {
  const responseBody = {
    entityTypes: ["passport_number"],
    count: 1,
    entities: [
      {
        entityType: "passport_number",
        value: "123456789",
        redactedValue: "123***789",
        confidence: 92,
        reason: "matched OCR text",
        source: { source: "photos", entityType: "photo", title: "Passport", resultID: "photo-1" },
        context: "Passport number is 123456789.",
      },
    ],
    searchedResults: 3,
    ocrResults: 1,
    ocrDocuments: [{ source: { resultID: "photo-1" }, text: "Passport number is 123456789.", lines: [] }],
    savedTo: "/tmp/passport.txt",
  };
  const { fetch, calls } = makeFetch(jsonResponse(responseBody));
  const client = new LimelightClient({ fetch });

  const response = await client.extract({
    entityTypes: ["passport_number"],
    text: "Passport number is 123456789.",
    path: "/tmp/passport.png",
    photoUUID: "photo-1",
    search: { queries: ["passport"], sources: ["photos"], limit: 50 },
    ocr: { enabled: true, maxItems: 12, recognitionLevel: "accurate", stopOnHighConfidence: true },
    saveTo: "/tmp/passport.txt",
    includeContext: true,
    includeOCRText: false,
  });

  assert.equal(calls[0].url, "http://127.0.0.1:8765/v1/extract");
  assert.deepEqual(JSON.parse(calls[0].init.body as string), {
    entityTypes: ["passport_number"],
    text: "Passport number is 123456789.",
    path: "/tmp/passport.png",
    photoUUID: "photo-1",
    search: { queries: ["passport"], sources: ["photos"], limit: 50 },
    ocr: { enabled: true, maxItems: 12, recognitionLevel: "accurate", stopOnHighConfidence: true },
    saveTo: "/tmp/passport.txt",
    includeContext: true,
    includeOCRText: false,
  });
  assert.equal(response.entities[0].redactedValue, "123***789");
  assert.equal(response.entities[0].source?.resultID, "photo-1");
});
