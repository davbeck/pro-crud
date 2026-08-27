# ProPresenter API Reference Guide

## Contents

- [Authoritative references](#authoritative-references)
- [Connection and trust boundary](#connection-and-trust-boundary)
- [Requests and responses](#requests-and-responses)
- [Identifiers and pagination](#identifiers-and-pagination)
- [Endpoint families](#endpoint-families)
- [Streaming updates](#streaming-updates)
- [TCP alternative](#tcp-alternative)
- [Operational safety](#operational-safety)
- [Troubleshooting](#troubleshooting)

## Authoritative references

- Interactive HTTP API reference: <https://openapi.propresenter.com/>
- Published specification asset: <https://openapi.propresenter.com/swagger.json>
- Official host, port, and network setup: <https://support.renewedvision.com/hc/en-us/articles/6024791423763-Connecting-to-ProPresenter-Control>
- Official TCP/IP alternative: <https://support.renewedvision.com/hc/en-us/articles/31606866768147-TCP-IP-Connections-with-ProPresenter-API>

The hosted specification declares OpenAPI 3.0.2 and describes its documentation as version `1.0`. That display version is not the API path version. Probe the unversioned `GET /version` endpoint and use its `api_version` value, such as `v1`, for versioned paths.

The specification asset is JavaScript beginning with `var openapi_spec =`, despite its `.json` filename. Strip that assignment before attempting to parse it as JSON. Prefer the interactive reference or the API Documentation button in ProPresenter for ordinary endpoint lookup.

The instance-local documentation best represents the installed version. Use the hosted reference as a fallback and recheck exact schemas when behavior differs.

## Connection and trust boundary

The documented server template is `http://localhost:{port}/`, with port `50001` as the default set in ProPresenter's Network preferences. Network services must be enabled in Settings > Network. For a client on another machine, use the IP address and port shown there and ensure both machines can communicate through the local network and firewall.

`GET /version` is intentionally unversioned. Its documented stable fields are:

- `name`
- `platform`
- `os_version`
- `host_description`
- `api_version`

The published specification defines no security schemes and declares no authentication requirements. Do not confuse passwords used by other ProPresenter remote-control products with HTTP API credentials. Because the documented transport is plain HTTP without declared authentication, treat access to the host and port as a network trust boundary; do not expose it to an untrusted network.

The API documents no host-discovery endpoint or protocol. Obtain the host and port from the operator instead of probing a subnet.

## Requests and responses

Use the exact method shown for the operation. ProPresenter deliberately uses `GET` for many operations that change state, including triggers, focus changes, clears, playback, timeline operations, timer operations, and navigation.

Common documented results include:

| Status | Meaning                                                                |
| ------ | ---------------------------------------------------------------------- |
| `200`  | Success with a response body.                                          |
| `204`  | Success with no response body. Do not wait for or decode JSON.         |
| `400`  | Invalid parameters or request body. Inspect the operation schema.      |
| `404`  | Network may be disabled, or the requested path/resource may not exist. |

A few thumbnail endpoints document `403` without defining a credential mechanism. Report that result as an installed-version or instance-policy behavior; do not invent an authorization header.

JSON request bodies are not always objects. Follow the operation schema when it requires an array, string, number, or boolean. Set `Content-Type: application/json`. There are no operations using `PATCH` in the current hosted specification, and `PUT` must not be assumed to merge with an existing value.

Thumbnail and chord-chart endpoints return image bytes. Check the operation's `Accept`, `thumbnail_type`, and `quality` behavior and write the response to a file. The `thumbnail_type` query parameter takes precedence over `Accept` where documented.

## Identifiers and pagination

Many `{id}` parameters accept a name, index, or UUID, but this varies by operation. Inspect the parameter schema rather than assuming all three forms are valid.

Prefer UUIDs obtained from a list or detail endpoint:

1. Query the relevant collection.
2. Match the intended item using returned metadata.
3. Retain its UUID.
4. URL-encode the UUID or other selected identifier as a path component.
5. Read the target detail or current state before changing it.

Indexes can change after reordering, and duplicate names can make name lookup ambiguous. Cue indexes used by presentation trigger routes respect the selected arrangement; use the exact returned or operator-specified index and treat it as zero-based where the operation documents that behavior.

Audio and media playlist-item listings return at most 100 items per request. Continue with the `start` query parameter until an empty page is returned when complete traversal is required.

## Endpoint families

Use the interactive reference for the complete operation list and schemas. The current hosted API organizes operations into these domains:

| Domain                        | Typical responsibilities                                                                  |
| ----------------------------- | ----------------------------------------------------------------------------------------- |
| Status                        | Version, layers, screens, current/next slide, aggregated updates.                         |
| Presentation and Announcement | Active/focused presentation state, cue details, thumbnails, focus, triggers, timelines.   |
| Playlist and Library          | Playlist trees and items, active/focused playlists, library contents, focus and triggers. |
| Looks and Clear               | Audience looks, layer clearing, configured clear groups.                                  |
| Macro                         | Macro and collection inspection, editing, icons, and triggering.                          |
| Stage                         | Stage messages, screens, layouts, and layout assignments.                                 |
| Timer and Transport           | Timer state and operations; playback position, play/pause, skipping, and auto-advance.    |
| Media, Audio, and Video Input | Playlists, items, thumbnails, active/focused state, and triggers.                         |
| Message, Prop, and Masks      | Saved display content, collections, thumbnails, show/clear operations.                    |
| Capture                       | Capture state, settings, encodings, start, and stop.                                      |
| Theme and Global Groups       | Theme slides and global group metadata.                                                   |
| Trigger                       | Convenience next/previous operations for active content.                                  |

Read-like names do not prove an endpoint is side-effect free, and action-like names do not reveal the HTTP method. Always inspect the individual operation.

## Streaming updates

The API uses long-lived chunked HTTP responses, optionally formatted as Server-Sent Events. It does not document WebSockets.

On an eligible `GET` endpoint:

- Add `chunked=true` to keep the response open and receive the normal response value whenever it changes.
- Add the `sse` query parameter to request Server-Sent Event formatting. Its value is irrelevant; presence enables it.
- Disable client-side response buffering.
- Close the connection explicitly when the subscription is no longer needed.

Browsers commonly limit concurrent connections per page. Consolidate several subscriptions with `POST /v1/status/updates`. Its body is an array of permitted relative paths without the `/v1/` prefix, for example:

```json
["status/slide", "timer/video_countdown"]
```

Aggregated JSON chunks contain `url` and `data`. With SSE, the source URL is the event name and the endpoint's native result is the event data. Updates are separated by CRLF-CRLF.

Some playlist and chord-chart update endpoints emit only `"change"`; re-fetch the corresponding resource after receiving that notification.

No heartbeat, event ID, resume cursor, or delivery guarantee is documented. A client should:

1. Define cancellation and timeouts.
2. Detect disconnects.
3. Reconnect with bounded exponential backoff and jitter.
4. Re-read current state after reconnecting instead of assuming no events were missed.
5. Avoid retrying any state-changing request as part of subscription recovery.

## TCP alternative

Renewed Vision also documents a raw TCP/IP adapter for systems without HTTP support. It is an alternative transport over a simple network socket, not a WebSocket API.

Each request and response is a one-line JSON value terminated by CRLF. A request contains:

- mandatory `url`, relative to the API root
- optional `method`
- optional `body` containing the full JSON value, not serialized JSON text
- optional `chunked` for streaming updates

A response contains the matching `url` and either `data` or `error`. An HTTP-equivalent `204 No Content` produces no TCP response. Follow the official TCP/IP article for transport setup and examples, and validate endpoint details against the HTTP API reference.

## Operational safety

Classify these as live-control operations even when they use `GET`:

- triggering presentations, cues, media, audio, video inputs, messages, props, macros, or clear groups
- moving focus or navigating active/focused items
- clearing layers or displayed content
- starting, stopping, pausing, rewinding, or seeking playback and timelines
- starting/stopping capture or changing timers
- changing live looks, screens, stage messages, or stage layouts

Triggers and macros can immediately alter audience screens, stage screens, playback, capture, or downstream automation. Do not prefetch action URLs, crawl the API indiscriminately, or automatically retry a request whose effect may already have happened.

`DELETE` operations can remove saved objects and, for collection endpoints, may remove contained objects. Before deletion, retrieve and present the exact UUID, name, and scope; require explicit authorization for that deletion; and verify afterward with a read-only request.

## Troubleshooting

Use this order:

1. Request `/version` from the exact host and port.
2. If the connection fails, confirm ProPresenter is running, Network is enabled, and firewall/routing permits the connection.
3. If `/version` returns `404`, recheck Network settings because the shared error description also covers a disabled network service.
4. Compare `api_version` with the versioned path prefix.
5. Open the target instance's API Documentation and confirm the operation exists in that installed version.
6. On `400`, validate every path/query parameter and the complete body type and fields.
7. On an empty `204`, treat the request as successful and verify with a separate read.
8. For streams, confirm the endpoint documents chunked support and that buffering is disabled.
9. For binary responses, remove JSON decoding and inspect response headers and file bytes.
