# Cache-busting the deployed web bundle

## Why this exists

On 2026-05-27 (PR #474) the production bundle was redeployed with
`adaptiveStream: false`, but at least one user's browser kept serving a cached
`main.dart.js` that still pinned `adaptiveStream: true`. The old and new
clients disagreed about whether the SFU should forward video, and they
couldn't see each other.

The root cause was not the code change. It was that `world.imagineering.cc`
served `main.dart.js` (and the rest of the Flutter web bundle) with no
`Cache-Control` directives, so browsers fell back to their heuristic caching.
Once a stale `main.dart.js` was pinned in cache, nothing in the deploy
pipeline forced a revalidation.

## The strategy

Two layers, working together.

### Layer 1 — query-string cache-buster on the bootstrap entry point

`web/index.html` references the Flutter bootstrap as
`flutter_bootstrap.js?v=BUILD_SHA`. The deploy workflow rewrites the literal
`BUILD_SHA` to the actual `GITHUB_SHA` of the commit being deployed
(`.github/workflows/deploy.yml`, "Stamp cache-busting query string" step).

The result: every deploy ships an `index.html` whose script URL is unique to
that commit. Browsers treat `flutter_bootstrap.js?v=abc123` and
`flutter_bootstrap.js?v=def456` as distinct resources and refetch.

`flutter_bootstrap.js` in turn references `main.dart.js` and the engine with
their own content-hashed URLs (Flutter's renderer already does this for those
downstream assets), so once the bootstrap is refreshed the rest of the chain
naturally invalidates.

### Layer 2 — `Cache-Control` headers in Caddy

Without the header layer, layer 1 still has a hole: `index.html` itself can
be cached. If a browser holds an old `index.html`, it'll keep loading the old
`flutter_bootstrap.js?v=<old-sha>` and never see the new pointer.

So Caddy must serve `index.html` and `flutter_bootstrap.js` with
`Cache-Control: no-cache, must-revalidate`. The browser may keep the file in
its cache, but it must revalidate with the server every load. Caddy will
respond `304 Not Modified` when the content hasn't changed and `200 OK` with
the fresh content when it has. Everything else (hashed `main.dart.js`,
fonts, images) keeps default ETag-based caching, which is correct because
those URLs change content-by-content.

### Runtime visibility — `APP_BUILD_SHA`

The workflow also passes `--dart-define=APP_BUILD_SHA=<sha>`. Dart code can
read it via `const String.fromEnvironment('APP_BUILD_SHA')` if we want to
surface the build SHA in a debug menu or a diagnostics event later. Not used
yet — added so the hook is there when we need to correlate user reports with
deployed commits.

## Caddyfile change (apply in `imagineering-infra`)

The Caddyfile lives in the `imagineering-infra` repo, not here. Paste the
following inside the existing `world.imagineering.cc { ... }` site block,
**before** the existing `handle { ... }` that proxies the file server:

```caddyfile
world.imagineering.cc {
    # Force revalidation on the HTML entry points so the cache-busting
    # query string in index.html (?v=<commit-sha>) actually reaches the
    # browser on every load. See tech_world docs/deploy/cache-busting.md.
    @entry_html {
        path / /index.html
    }
    header @entry_html Cache-Control "no-cache, must-revalidate"

    @bootstrap {
        path /flutter_bootstrap.js
    }
    header @bootstrap Cache-Control "no-cache, must-revalidate"

    handle {
        root * /srv/tech-world
        file_server
        try_files {path} /index.html
    }

    # ... existing /avatar* reverse_proxy blocks unchanged ...
}
```

After editing, reload Caddy inside the container:

```bash
ssh nick@149.118.69.221 'docker exec caddy caddy reload --config /etc/caddy/Caddyfile'
```

## Verifying the deploy

After a deploy, from any browser:

1. View source on `https://world.imagineering.cc/` and confirm the script tag
   includes `flutter_bootstrap.js?v=<commit-sha>`.
2. In DevTools Network tab, hard-reload and check the response headers on
   `/` and `/flutter_bootstrap.js` — both should include
   `cache-control: no-cache, must-revalidate`.
3. On a soft reload (no DevTools), `flutter_bootstrap.js` should return
   `304 Not Modified` if the SHA hasn't changed, and `200 OK` if it has.

## Where this lives

- `web/index.html` — placeholder `?v=BUILD_SHA` literal on the bootstrap.
- `.github/workflows/deploy.yml` — `Stamp cache-busting query string` step
  rewrites the literal to `GITHUB_SHA`.
- `imagineering-infra` (separate repo) — Caddy site definition for
  `world.imagineering.cc` with the `Cache-Control` headers above.
