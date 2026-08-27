---
name: propresenter-api
description: Inspect, automate, and control a running ProPresenter instance through its official local HTTP API, including presentations, playlists, looks, layers, timers, stage displays, media, capture, and chunked or SSE status streams. Use when building or troubleshooting ProPresenter API clients, constructing requests, querying live state, or performing remote-control operations.
---

# ProPresenter API

Use the official ProPresenter API to inspect or control a running ProPresenter instance. Treat it as a live production control surface: the meaning of an operation, not its HTTP method, determines whether it is safe.

Read [references/api-reference.md](references/api-reference.md) before implementing a client, choosing endpoints, subscribing to updates, or diagnosing protocol errors.

## Workflow

1. Establish the target.
   - Obtain the host and API port from ProPresenter's Settings > Network screen. Network must be enabled.
   - Use `127.0.0.1` only when the client runs on the ProPresenter machine. Port `50001` is the documented default, not a value to assume for another installation.
   - Do not scan a network for ProPresenter instances; the API documents no discovery mechanism.
2. Probe `GET /version` before using a versioned endpoint. Read `api_version` from the response and select matching paths, currently `/v1/...` in the public reference.
3. Open the API Documentation from the target instance's Network settings when possible. Otherwise use the official reference at <https://openapi.propresenter.com/>. Verify the exact method, path, parameters, body, response, and installed-version support for every operation.
4. Classify the operation by effect.
   - Read-only requests retrieve state, lists, details, or images.
   - Live-control requests include trigger, focus, clear, transport, timeline, timer, capture, and navigation operations—even when they use `GET`.
   - Destructive requests can delete saved configuration or content.
5. Before sending a live-control or destructive request, read the relevant current state, resolve the exact target, and obtain confirmation unless the user's current request already explicitly authorizes that action on that instance. Never prefetch, crawl, or automatically retry a state-changing URL.
6. Prefer a UUID returned by a list or detail endpoint over a name or index. Names can be ambiguous and indexes can change. URL-encode every dynamic path component.
7. Send only the documented body shape. Set `Content-Type: application/json` for JSON, do not invent authentication headers, and do not assume `PUT` is a partial update. The published API defines no `PATCH` operations.
8. Verify a change with a read-only request. Treat `204 No Content` as success without attempting to parse a body.

## Request templates

Start with a read-only probe:

```sh
PP_API_BASE_URL=http://127.0.0.1:50001
curl --fail-with-body --silent --show-error "$PP_API_BASE_URL/version" | jq .
curl --fail-with-body --silent --show-error "$PP_API_BASE_URL/v1/status/slide" | jq .
```

For JSON input, preserve the exact documented JSON type; a body may be an object, array, string, number, or boolean:

```sh
curl --fail-with-body --silent --show-error \
  --request PUT \
  --header 'Content-Type: application/json' \
  --data "$REQUEST_JSON" \
  "$PP_API_BASE_URL/v1/documented/path"
```

Do not substitute a live path into the mutation template until its effect and target are authorized. Save thumbnail and chord-chart responses as binary files instead of piping them to `jq`.

## Streaming

Use chunked HTTP or Server-Sent Events only on endpoints that document streaming support:

```sh
curl --fail-with-body --silent --show-error --no-buffer \
  "$PP_API_BASE_URL/v1/status/slide?chunked=true&sse"
```

For several subscriptions, prefer `POST /v1/status/updates` with its documented array of relative endpoint paths. Implement explicit cancellation and bounded reconnect/backoff. The protocol documents no WebSocket API, heartbeat, resume cursor, or delivery guarantee.

## Failure handling

- On connection failure, confirm ProPresenter is running, Network is enabled, the displayed host and port are correct, and local firewall/routing permits the connection.
- A documented `404` can mean either Network is disabled or the path is absent. Recheck `/version` and the target instance's API Documentation.
- On `400`, compare path parameters and the complete JSON body with the exact operation schema.
- Expect capabilities to vary by installed ProPresenter version. Do not replace evidence from the live instance with assumptions from a newer hosted reference.
