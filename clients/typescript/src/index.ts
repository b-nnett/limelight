export type JSONPrimitive = string | number | boolean | null;
export type JSONValue = JSONPrimitive | JSONValue[] | { [key: string]: JSONValue };
export type Metadata = Record<string, JSONValue>;

export type SearchSource =
  | "files"
  | "photos"
  | "contacts"
  | "calendar"
  | "reminders"
  | "notes"
  | "mail"
  | "messages"
  | "safari"
  | string;

export type SearchType =
  | "application"
  | "document"
  | "image"
  | "audio"
  | "video"
  | "folder"
  | "archive"
  | "source"
  | string;

export interface LimelightClientOptions {
  baseUrl?: string;
  authToken?: string;
  fetch?: typeof fetch;
}

export interface HealthResponse {
  status: string;
  spotlightIndexingEnabled: boolean;
  providers: string[];
}

export interface SearchRequest {
  query: string;
  types?: SearchType[];
  sources?: SearchSource[];
  onlyIn?: string[];
  limit?: number;
}

export interface SearchResult {
  id: string;
  source: string;
  entityType: string;
  title: string;
  subtitle?: string | null;
  path?: string | null;
  url?: string | null;
  contentType?: string | null;
  createdAt?: string | null;
  modifiedAt?: string | null;
  startAt?: string | null;
  endAt?: string | null;
  authors?: string[] | null;
  sizeBytes?: number | null;
  metadata: Metadata;
}

export interface ProviderSearchStatus {
  source: string;
  status: string;
  count: number;
  error?: string | null;
}

export interface SearchResponse {
  query: string;
  count: number;
  limit: number;
  results: SearchResult[];
  providers: ProviderSearchStatus[];
}

export interface DeepSearchRequest {
  queries: string[];
  regexes?: string[];
  types?: SearchType[];
  sources?: SearchSource[];
  onlyIn?: string[];
  limitPerQuery?: number;
  limit?: number;
}

export interface DeepSearchResult {
  result: SearchResult;
  matchedQueries: string[];
  matchedRegexes: string[];
  score: number;
}

export interface DeepSearchResponse {
  queries: string[];
  regexes: string[];
  count: number;
  limit: number;
  results: DeepSearchResult[];
  providers: ProviderSearchStatus[];
}

export interface OCRRequest {
  path?: string;
  photoUUID?: string;
  recognitionLevel?: string;
  languages?: string[];
  includeText?: boolean;
}

export interface OCRLine {
  text: string;
  confidence: number;
}

export interface OCRResponse {
  sourcePath: string;
  photoUUID?: string | null;
  text?: string | null;
  lines: OCRLine[];
}

export interface ExtractOCRRequest {
  enabled?: boolean;
  maxItems?: number;
  recognitionLevel?: string;
  stopOnHighConfidence?: boolean;
}

export interface ExtractRequest {
  entityTypes: string[];
  text?: string;
  path?: string;
  photoUUID?: string;
  search?: DeepSearchRequest;
  ocr?: ExtractOCRRequest;
  saveTo?: string;
  includeContext?: boolean;
  includeOCRText?: boolean;
}

export interface ExtractionSource {
  source?: string | null;
  entityType?: string | null;
  title?: string | null;
  path?: string | null;
  url?: string | null;
  photoUUID?: string | null;
  resultID?: string | null;
}

export interface OCRDocument {
  source?: ExtractionSource | null;
  text: string;
  lines: OCRLine[];
}

export interface ExtractedEntity {
  entityType: string;
  value: string;
  redactedValue: string;
  confidence: number;
  reason: string;
  source?: ExtractionSource | null;
  context?: string | null;
}

export interface ExtractResponse {
  entityTypes: string[];
  count: number;
  entities: ExtractedEntity[];
  searchedResults: number;
  ocrResults: number;
  ocrDocuments: OCRDocument[];
  savedTo?: string | null;
}

export interface ProviderReadinessCheck {
  name: string;
  status: string;
  path?: string | null;
  message?: string | null;
}

export interface ProviderReadiness {
  source: string;
  status: string;
  summary: string;
  setupHint?: string | null;
  checks: ProviderReadinessCheck[];
}

export interface ProvidersResponse {
  providers: ProviderReadiness[];
}

export interface ProviderSchema {
  entityTypes: string[];
  fields: Record<string, string>;
  metadataFields: Record<string, string>;
}

export interface SchemaResponse {
  normalizedFields: Record<string, string>;
  supportedTypes: string[];
  supportedSources: string[];
  metadataAttributes: string[];
  providerFields: Record<string, ProviderSchema>;
}

export interface SourceCapability {
  source: string;
  entityTypes: string[];
  permissionRequired: string;
  liveStatus: string;
  summary: string;
  supportedFields: string[];
  limitations: string[];
  setupHint?: string | null;
}

export interface CapabilitiesResponse {
  generatedAt: string;
  sources: SourceCapability[];
}

export interface PermissionAction {
  source: string;
  status: string;
  message: string;
  setupHint?: string | null;
}

export interface PermissionResponse {
  results: PermissionAction[];
}

export interface SpotlightRecord {
  id: string;
  source?: string | null;
  entityType?: string | null;
  title?: string | null;
  subtitle?: string | null;
  path?: string | null;
  url?: string | null;
  displayName?: string | null;
  contentType?: string | null;
  kind?: string | null;
  bundleIdentifier?: string | null;
  createdAt?: string | null;
  modifiedAt?: string | null;
  authors?: string[] | null;
  sizeBytes?: number | null;
  metadata: Metadata;
}

export interface ItemResponse {
  item: SpotlightRecord;
}

export interface ItemLookup {
  path?: string;
  source?: SearchSource;
  id?: string;
}

export interface OpenItemRequest {
  path?: string;
  source?: SearchSource;
  id?: string;
  url?: string;
}

export interface OpenItemResponse {
  opened: boolean;
  target: string;
  item?: SpotlightRecord | null;
}

export class LimelightError extends Error {
  readonly status: number;
  readonly body: string;

  constructor(status: number, body: string) {
    super(`${status}: ${body}`);
    this.name = "LimelightError";
    this.status = status;
    this.body = body;
  }
}

export class LimelightClient {
  private readonly baseUrl: string;
  private readonly authToken?: string;
  private readonly fetchImpl: typeof fetch;

  constructor(options: LimelightClientOptions = {}) {
    this.baseUrl = (options.baseUrl ?? "http://127.0.0.1:8765").replace(/\/+$/, "");
    this.authToken = options.authToken;
    const fetchImpl = options.fetch ?? globalThis.fetch;
    if (!fetchImpl) {
      throw new Error("LimelightClient requires global fetch or an explicit fetch implementation.");
    }
    this.fetchImpl = fetchImpl;
  }

  health(): Promise<HealthResponse> {
    return this.request("GET", "/health");
  }

  providers(): Promise<ProvidersResponse> {
    return this.request("GET", "/v1/providers");
  }

  schema(): Promise<SchemaResponse> {
    return this.request("GET", "/v1/schema");
  }

  capabilities(): Promise<CapabilitiesResponse> {
    return this.request("GET", "/v1/capabilities");
  }

  requestPermissions(sources?: SearchSource[]): Promise<PermissionResponse> {
    return this.request("POST", "/v1/permissions/request", sources ? { sources } : {});
  }

  item(pathOrLookup: string | ItemLookup): Promise<ItemResponse> {
    const lookup = typeof pathOrLookup === "string" ? { path: pathOrLookup } : pathOrLookup;
    const params = new URLSearchParams();
    if (lookup.path !== undefined) {
      params.set("path", lookup.path);
    }
    if (lookup.source !== undefined) {
      params.set("source", lookup.source);
    }
    if (lookup.id !== undefined) {
      params.set("id", lookup.id);
    }
    return this.request("GET", `/v1/item?${params}`);
  }

  openItem(request: string | OpenItemRequest): Promise<OpenItemResponse> {
    const payload = typeof request === "string" ? { path: request } : request;
    return this.request("POST", "/v1/open", payload);
  }

  async search(request: SearchRequest | string): Promise<SearchResult[]> {
    const response = await this.searchResponse(request);
    return response.results;
  }

  searchResponse(request: SearchRequest | string): Promise<SearchResponse> {
    const payload = typeof request === "string" ? { query: request } : request;
    return this.request("POST", "/v1/search", payload);
  }

  deepSearch(request: DeepSearchRequest): Promise<DeepSearchResponse> {
    return this.request("POST", "/v1/deep-search", request);
  }

  ocr(request: OCRRequest): Promise<OCRResponse> {
    return this.request("POST", "/v1/ocr", request);
  }

  extract(request: ExtractRequest): Promise<ExtractResponse> {
    return this.request("POST", "/v1/extract", request);
  }

  photoThumbnail(assetId: string): Promise<ArrayBuffer> {
    return this.requestBinary(`/v1/photos/thumbnail?${new URLSearchParams({ id: assetId })}`);
  }

  photoThumbnailByUUID(uuid: string): Promise<ArrayBuffer> {
    return this.requestBinary(`/v1/photos/thumbnail?${new URLSearchParams({ uuid })}`);
  }

  private async request<T>(method: string, path: string, payload?: unknown): Promise<T> {
    const headers = new Headers();
    headers.set("Accept", "application/json");

    let body: string | undefined;
    if (payload !== undefined) {
      headers.set("Content-Type", "application/json");
      body = JSON.stringify(payload);
    }

    if (this.authToken) {
      headers.set("Authorization", `Bearer ${this.authToken}`);
    }

    const response = await this.fetchImpl(`${this.baseUrl}${path}`, { method, headers, body });
    if (!response.ok) {
      throw new LimelightError(response.status, await response.text());
    }

    return (await response.json()) as T;
  }

  private async requestBinary(path: string): Promise<ArrayBuffer> {
    const headers = new Headers();
    if (this.authToken) {
      headers.set("Authorization", `Bearer ${this.authToken}`);
    }

    const response = await this.fetchImpl(`${this.baseUrl}${path}`, { method: "GET", headers });
    if (!response.ok) {
      throw new LimelightError(response.status, await response.text());
    }

    return response.arrayBuffer();
  }
}
