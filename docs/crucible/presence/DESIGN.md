# Presence — who is in a room, and who is allowed to say so

**Status:** design, untempered. Written 2026-09-15 after the PR #530 delta cage-match
extracted the TTL sweep (`692afb9e`, reverting `77c68377`).
**Tracker:** claude-tasks#4294 (this decision), #4266 (the ghosts), #3160 (guest uid growth).

## The question

The foyer lists who is in each room, **including rooms the viewer has not joined**. Today
that list comes from a Firestore `/presence` collection that CLIENTS write: a document on
entry, a delete on graceful exit. LiveKit — which actually knows who is connected — is
never asked.

The question is not "how do we stop the ghosts". It is **who owns the fact**, and the
answer decides whether ghosts are a bug to be reaped or a state that cannot be represented.

## Why the patch was extracted rather than repaired

The TTL sweep + heartbeat shipped on 2026-09-11 and was reverted on 2026-09-15. It is worth
being precise about why, because "it had bugs" is the wrong lesson:

1. **It compared a Firestore SERVER timestamp against the observer's LOCAL clock.** A viewer
   whose device runs more than the TTL fast filters out users immediately after their
   heartbeat lands. Occupancy became a function of who was looking. Note the direction: the
   old bug showed people who had left; this one **hides people who are there** — the outcome
   the heartbeat existed to prevent.
2. **The filter had no clock.** Staleness was evaluated only inside
   `.snapshots().map(...)`, so it ran only when Firestore EMITTED. After an ungraceful exit
   nothing writes, nothing re-emits, and the ghost stays — the exact six-hours-later case
   the docstring cited as motivation. The sweep only swept when somebody else happened to
   write.

Neither defect is reachable without changing what presence IS. Both are what a mirror does
when you ask it to answer a question about liveness. That is the finding, and it is an
argument about ownership rather than about implementation quality.

## Options

### (a) Eviction signal — LiveKit `participant_left` webhook → Cloud Function deletes the doc

Keeps the collection and the read path. Adds the one thing the mirror lacks: a reliable
signal that someone is gone.

- **Still a mirror.** Two stores can still disagree; this narrows the window, it does not
  close it. A missed webhook (delivery failure, function cold-start error, a redeploy) is
  silent and leaves a ghost with nothing to reap it — the TTL sweep was the backstop for
  exactly that, and it is the thing we just removed.
- Cross-repo: `tech_world_firebase_functions`, plus webhook config on the self-hosted
  LiveKit box.
- Rows still accumulate per ungraceful exit until a webhook lands; with disposable guest
  uids (#3160) that is unbounded.

### (b) Derive occupancy from LiveKit, delete `/presence`

The foyer asks a server endpoint; the endpoint asks LiveKit; there is one store and nothing
to reconcile. Ghosts become **unrepresentable** rather than reaped.

- Needs a server-side roster query, because a client cannot query a room it has not joined.
- **This is cheaper than when #4294 was written, and that is verified, not assumed.**
  `realm-token-server` already depends on `livekit-server-sdk@^2.15.0` — which ships
  `RoomServiceClient.listRooms` / `listParticipants` — already holds `LIVEKIT_API_KEY` /
  `LIVEKIT_API_SECRET`, is already deployed, and is already fronted by Caddy with a working
  auth path. The capability is present and unused; this is an endpoint, not a service.
- Costs: a LiveKit API call per foyer read (cacheable, and the foyer is not hot); the foyer
  gains a hard dependency on LiveKit being up, where today it degrades to a stale list.

## The load-bearing premises, stated so they can be attacked

1. **The foyer must show occupancy for rooms the viewer has not joined.** If this is false,
   (b) collapses to a client-side query and the whole server-side question evaporates.
2. **LiveKit is the authority on who is connected.** If rooms can hold meaningful presence
   for participants LiveKit does not know about (a lurker, a spectator, a queued player),
   then neither option is complete.
3. **A foyer that fails closed when LiveKit is down is acceptable.** (b) trades a stale list
   for an empty one. That is a product call, not an engineering one.
4. **Nothing else reads `/presence`.** If another surface consumes it, deleting the
   collection is a wider change than this note accounts for.

## Recommendation

**(b)**, and the reasoning is not "it is the honest end state" — it is that (a) re-creates
the reaper we just deleted. Option (a)'s failure mode (a missed webhook) needs a TTL sweep
as backstop, and the TTL sweep is what two independent cage-match findings just condemned.
Choosing (a) means re-introducing the mechanism whose removal this design exists to justify.

The blocker that made (b) expensive has already been paid for by the realm-token-server
work, which is the fact that changed since #4294 was written.

## Success criterion

The `/presence` collection and the heartbeat are both **deleted**, not merely bypassed. A
per-minute write whose reader is gone is how the next vestigial mechanism is created.
