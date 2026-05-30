# URL Consolidation Runbook — Decommission non-canonical Tech World hosts

**Status:** runbook (Nick to execute against the Firebase project)
**Last updated:** 2026-05-30
**Canonical URL:** `https://world.imagineering.cc`
**Owner of action:** Nick (requires Firebase console + DNS access)

---

## Why this exists

On 2026-05-30 a user (Robin) loaded Tech World from
`https://adventures-in-tech-world-0.web.app` and ran into the old
`livekit_client` build that ships `adaptiveStream: true` — the SFU stopped
forwarding tracks and they could not see/hear other players.

The stale bundle is dated **Fri, 24 Apr 2026** (5+ weeks old).
PR #284 (2026-04-27) removed the Firebase Hosting deploy step from CI and
switched the canonical pipeline to rsync onto `world.imagineering.cc`, but it
did **not** decommission the existing Firebase Hosting site. Result: the
Firebase Hosting CDN kept serving the last build it received, indefinitely,
to anyone who still had the URL.

### Hosts that have served Tech World (verified 2026-05-30)

| Host | Status (2026-05-30) | Last-Modified | Action |
|---|---|---|---|
| `world.imagineering.cc` | HTTP 200, current build | Wed, 27 May 2026 | **canonical — keep** |
| `adventures-in-tech-world-0.web.app` | HTTP 200, stale | Fri, 24 Apr 2026 | **decommission** |
| `adventures-in-tech-world-0.firebaseapp.com` | HTTP 200, stale | Fri, 24 Apr 2026 | **decommission** |
| `adventures-in-tech.world` | HTTP 200, stale | Fri, 24 Apr 2026 | **decommission** (Firebase Hosting custom domain) |
| `tech-world-app.web.app` | HTTP 404 | — | already gone |

All three "decommission" hosts are served by the **same** Firebase Hosting
site (`adventures-in-tech-world-0`). Disabling or redirecting that one site
handles all three at once.

---

## Recommendation: REDIRECT (not disable)

Two options to stop the bleed. **Default recommendation: redirect.**

| Option | Pros | Cons |
|---|---|---|
| **Disable** (`firebase hosting:disable`) | One command, honest "this URL is gone" 404 | Breaks every stale bookmark / Discord link / email signature / grant doc that ever pointed at the old URL |
| **Redirect** (deploy a `firebase.json` with `hosting.redirects`) | Stale bookmarks land on the canonical URL; UX continuity | Requires keeping the Firebase Hosting site alive and deploying a tiny redirect shim |

Going with **redirect** for a 6-month deprecation window (until 2026-11-30),
then disable. Rationale: the user impact of breaking a stale URL is worse
than the operational cost of a shim that has zero ongoing maintenance.

Note: even with the redirect option, the `hosting` block has been **removed
from the main repo `firebase.json`** so that a future `firebase deploy --only
hosting` from this repo cannot accidentally publish the Flutter build to the
stale site. The redirect shim is a **separate, minimal config** deployed
once and left alone (see Step 2 below).

---

## Step 1 — Prep (Nick, ~2 min)

```bash
# Confirm logged in to the right Google account
firebase login:list

# Confirm the project
firebase projects:list | grep adventures-in-tech-world-0

# Snapshot the current hosting state for the audit trail
firebase hosting:sites:list --project adventures-in-tech-world-0
firebase hosting:channel:list --project adventures-in-tech-world-0 --site adventures-in-tech-world-0
```

---

## Step 2 — Deploy the redirect shim (recommended path)

Create a throwaway directory **outside** the tech_world repo so its
`firebase.json` cannot collide with this repo's config:

```bash
mkdir -p /tmp/tw-redirect-shim && cd /tmp/tw-redirect-shim

cat > firebase.json <<'EOF'
{
  "hosting": {
    "site": "adventures-in-tech-world-0",
    "public": "public",
    "ignore": ["firebase.json", "**/.*"],
    "redirects": [
      {
        "source": "**",
        "destination": "https://world.imagineering.cc/:1",
        "type": 301
      }
    ]
  }
}
EOF

mkdir -p public
cat > public/index.html <<'EOF'
<!doctype html>
<html><head>
<meta charset="utf-8">
<title>Tech World has moved</title>
<meta http-equiv="refresh" content="0; url=https://world.imagineering.cc/">
<link rel="canonical" href="https://world.imagineering.cc/">
</head><body>
<p>Tech World now lives at
<a href="https://world.imagineering.cc/">https://world.imagineering.cc/</a>.
Redirecting…</p>
</body></html>
EOF

firebase deploy --only hosting --project adventures-in-tech-world-0
```

The `**` source matches every path; `:1` interpolates the captured path so
`/room/foo` redirects to `https://world.imagineering.cc/room/foo`. The
`index.html` is the meta-refresh fallback for the rare client that doesn't
honour the 301.

**Caveat on the redirect's reach.** Firebase Hosting's `redirects` config
applies to every domain attached to the site — that's
`adventures-in-tech-world-0.web.app`, `*.firebaseapp.com`, and the
`adventures-in-tech.world` custom domain. All three start redirecting at the
same instant. There is no per-domain redirect knob.

---

## Step 3 — Verify (Nick, ~1 min)

```bash
# Expect: HTTP/2 301, location: https://world.imagineering.cc/
curl -sI https://adventures-in-tech-world-0.web.app/ | head -5
curl -sI https://adventures-in-tech-world-0.firebaseapp.com/ | head -5
curl -sI https://adventures-in-tech.world/ | head -5

# Expect: HTTP/2 301 to https://world.imagineering.cc/room/foo
curl -sI https://adventures-in-tech-world-0.web.app/room/foo | head -5

# Sanity check: canonical still works
curl -sI https://world.imagineering.cc/ | head -3
```

If any of the three stale hosts returns 200 with the old `main.dart.js`
last-modified date, the deploy did not take — re-run Step 2 with
`--debug`.

---

## Step 4 — Apply the cors.json change to the Storage bucket

**⚠️ Critical — this step is NOT done by merging the PR.** The `cors.json`
file in the repo is documentation of *intent* — `firebase deploy` does NOT
push it to Firebase Storage. The bucket policy is applied separately via
`gcloud` (or legacy `gsutil`).

**Sequence rule**: apply this AFTER the redirect from Step 2 is live and
verified by Step 3's curls. If you apply the new CORS allowlist before
the redirect is in place, any user still loading the app from a stale
host will hit silent Storage failures (avatar uploads, custom map
imports, profile pictures) — the exact failure mode the redirect strategy
is meant to prevent. Real consumers of the bucket are in
`lib/auth/profile_picture_service.dart` and
`lib/flame/tiles/tileset_storage_service.dart`.

```bash
# Apply the canonical-only CORS allowlist from the repo's cors.json.
# Run from the tech_world repo root so cors.json is current.
cd ~/path/to/tech_world

# Modern gcloud syntax (preferred):
gcloud storage buckets update gs://adventures-in-tech-world-0.firebasestorage.app \
  --cors-file=cors.json

# Or legacy gsutil:
# gsutil cors set cors.json gs://adventures-in-tech-world-0.firebasestorage.app
```

**Verify**:

```bash
# Read back the live CORS config; expect ONLY world.imagineering.cc as origin.
gcloud storage buckets describe gs://adventures-in-tech-world-0.firebasestorage.app \
  --format='value(cors_config)' | head -20

# Real-traffic check from canonical (preflight expected to succeed):
curl -sI -X OPTIONS \
  -H "Origin: https://world.imagineering.cc" \
  -H "Access-Control-Request-Method: GET" \
  "https://firebasestorage.googleapis.com/v0/b/adventures-in-tech-world-0.firebasestorage.app/o" \
  | grep -iE "access-control|http"
# Expect: access-control-allow-origin: https://world.imagineering.cc

# Stale-origin preflight should now be denied (this is the desired outcome
# AFTER the redirect is live — users hitting stale hosts get the 301
# before they reach Storage).
curl -sI -X OPTIONS \
  -H "Origin: https://adventures-in-tech-world-0.web.app" \
  -H "Access-Control-Request-Method: GET" \
  "https://firebasestorage.googleapis.com/v0/b/adventures-in-tech-world-0.firebasestorage.app/o" \
  | grep -iE "access-control|http"
# Expect: no access-control-allow-origin header (CORS denied)
```

If either canonical check fails, roll back by re-applying the prior
allowlist (keep a copy of the old `cors.json` before this step):

```bash
gcloud storage buckets update gs://adventures-in-tech-world-0.firebasestorage.app \
  --cors-file=cors-prev.json
```

---

## Step 5 — Alternative: hard disable (if redirect rejected)

Skip Step 2 entirely and run:

```bash
firebase hosting:disable --project adventures-in-tech-world-0 --site adventures-in-tech-world-0
```

This puts up Firebase's "Site Not Found" page on all three hosts. Verify
with the same curl commands as Step 3 — expect HTTP 404.

Step 4 (apply `cors.json` to the bucket) still applies on the disable
path — `firebase hosting:disable` only touches Hosting, not Storage
CORS.

---

## Step 6 — Update external references

The codebase scan (2026-05-30) found these in-repo URL references; all
have been updated to canonical in this PR:

- `web/index.html` — added `<link rel="canonical">` + Open Graph `og:url`
- `web/manifest.json` — `start_url`, `scope`, `id` now point at canonical
- `cors.json` — Firebase Storage CORS allowlist trimmed to canonical only
- `docs/grant-application/prototype-details.md` — three URL references updated

Out-of-repo references for Nick to sweep manually after the redirect lands:

- **Discord pinned messages** in the tech_world server — replace any
  `adventures-in-tech-world-0.web.app` or `adventures-in-tech.world` link
- **Email signature / meetup announcements** — Adventures In meetup invites
  historically used `adventures-in-tech.world`
- **Screen Australia grant application** — the submitted PDF version of
  `docs/grant-application/prototype-details.md` still references
  `adventures-in-tech.world`. If the grant is still under review, file a
  correction; if already submitted, the redirect handles new evaluators
  clicking through
- **bot READMEs in `../tech_world_bot/`** — grep for any docs that link
  back to the user-facing URL
- **Social cards / og-image previews** cached at Twitter / Facebook /
  Discord — these refresh from `og:url`, so the canonical update in
  `web/index.html` propagates automatically once `world.imagineering.cc`
  re-deploys

---

## Step 7 — Don't break Firebase Auth

The Firebase Auth callback at
`adventures-in-tech-world-0.firebaseapp.com/__/auth/handler` is the OAuth
return URL embedded in `lib/firebase_options.dart` as `authDomain`. Sign-in
flow needs this path to keep returning 200.

**Both options preserve it.** The `__/auth/*` paths are reserved by Firebase
and not affected by the user-defined `hosting.redirects` (`hosting:disable`
likewise leaves the auth handler alone — disable only kills the user site,
not the Firebase-managed auth paths). After deploy, verify:

```bash
curl -sI https://adventures-in-tech-world-0.firebaseapp.com/__/auth/handler | head -3
# Expect: HTTP/2 200 (Firebase serves the auth handler regardless)
```

If this ever returns 404, sign-in is broken and the redirect must be rolled
back (`firebase hosting:clone` from a prior release or re-deploy without
the `**` redirect).

---

## Rollback

If the redirect deploy breaks something:

```bash
cd /tmp/tw-redirect-shim
# Edit firebase.json to remove the redirects block, then:
firebase deploy --only hosting --project adventures-in-tech-world-0
# Or: revert to a prior release via the Firebase console (Hosting → Release history → Rollback)
```

The Firebase console's release-history rollback is the fastest emergency
revert and does not require local CLI state.

---

## Post-action

After Step 3 verification passes, append a one-liner to MEMORY.md under
"Recently Shipped" so future sessions know the old URLs are dead/redirected
and don't waste cycles debugging "stale bundle" reports.
