# Web, API, And Runtime

Use this reference for web challenges, API challenges, SSR/frontend issues, queue-backed app flows, or any case where browser state and request order matter.

## Default Ladder

1. Inspect entry HTML, boot scripts, route registration, hydration data, and runtime config.
2. Inspect browser persistence: cookies, localStorage, sessionStorage, IndexedDB, Cache Storage, service workers, and transient globals.
3. Capture the real request order before theorizing from source.
4. Map backend entrypoints, middleware order, handlers, workers, retries, and downstream state changes.
5. Re-run the smallest flow with one variable changed.

## High-Value Targets

- Hidden routes, debug pages, preview modes, experiment toggles, alternate hostnames
- Auth and session flow: minting, refresh, header injection, role derivation, cookie scope
- Upload, import, export, template, archive, and deserialization boundaries
- Background jobs, queues, cron tasks, and event consumers
- Host-header handling, base-URL derivation, proxy headers, path-prefix routing

## Evidence To Keep

- Exact requests: host, path, query, headers, cookies, and body
- Exact responses or failures that reveal parser behavior or hidden branches
- Storage keys, feature flags, worker names, and queue payloads
- Concrete file paths, function names, route names, or runtime hook points

## Common Pitfalls

- Treating UI gating as backend enforcement
- Trusting checked-in source over actively served assets
- Missing the real request order because only the visible UI was inspected
- Ignoring container/proxy routing inputs such as `Host` or forwarded headers
