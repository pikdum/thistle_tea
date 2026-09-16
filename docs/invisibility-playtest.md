# Invisibility and detection

Unit invisibility and detection now use aura types 18 and 19. The pure
`Logic.Invisibility` module derives the strongest active level per type.
Matching detection at or above that level, a shared invisibility type, or
world-boss detection reveals a target. Drunkenness supplies type-6 detection.
Owned companions and party members remain visible through the visibility
boundary. This adds unit invisibility; it does not replace stealth detection
or implement game-object trap detection.

References: `Unit::CanDetectInvisibilityOf` and the invisibility branch of
unit visibility in `refs/vmangos/src/game/Objects/Unit.cpp`, plus
`Aura::HandleInvisibility` and `Aura::HandleInvisibilityDetect` in
`refs/vmangos/src/game/Spells/SpellAuras.cpp`.

Player and creature owners publish detection metadata. Aura and group changes
refresh observer visibility. Outbound object updates, including queued batch
members, are filtered again before serialization so stale creates cannot
reveal hidden units. Creature aggro and victim selection, player targeting,
and melee/ranged behavior consult invisibility. Action-start, action-completion,
and attack interrupt flags remove affected auras through the existing lifecycle.

## Bug found during acceptance

Right-clicking Detect Greater Invisibility originally removed its aura but
left its detection metadata and visible objects unchanged. The old cancel
handler sent field updates directly and skipped the owning player's publication
path. Cancellation now dispatches into `Player.Spells.cancel_aura/2`, then uses
the owner's normal metadata, effect, broadcast, and scheduling path. A boundary
regression verifies that removing strong detection publishes the weaker level
and destroys an insufficiently detectable target. Creature metadata is also
published before its object updates.

## Real-client acceptance

Two isolated build-5875 clients used level-50 Debugwarlock (GUID 6, observer)
and Debugshaman (GUID 8, subject) on Programmer Isle. Input came from client
spell casts, item use, buff-icon right-clicks, targeting, and melee attacks.
Read-only Tidewave samples checked owners, metadata, inventory, and tracked
objects alongside screenshots.

- Before invisibility, the observer could see and target the subject.
- Spell 885 applied type-0 invisibility at level 200 and player glow flag 64.
  The observer's Lesser Detection at level 100 could not reveal it: the model
  and target frame disappeared, and the subject was no longer tracked.
- Detect Greater Invisibility (11743) supplied level 300 and revealed the
  still-invisible subject. After the cancellation fix, right-clicking that buff
  restored level 100 and removed the subject from view and tracking again.
- Cancelling the subject's invisibility restored normal visibility.
- Using an actual Invisibility Potion (9172, spell 11392) consumed one of two
  items. Sampling observed normal visibility, level-200 invisibility with glow
  64 and tracking removed, then normal visibility and glow 0 after 18 seconds.
  The remaining item count stayed at one.
- While invisible, the subject stood 1.80 yards from a Skeletal Flayer without
  either entering combat. Completing Healing Wave removed invisibility; the
  creature acquired GUID 8 and began dealing damage. The client showed combat.
- Starting a melee attack on a nearby rabbit removed invisibility and the glow,
  delivered the attack, and subsequently left combat.

The final server session had no owner, visibility, movement, or gameplay errors.
An earlier force-recompile attempt was discarded after disrupting live modules;
acceptance used a fresh server. The cancellation fix was loaded by replacing
only its three compiled modules, then the failed scenario was repeated.

Evidence is retained in:

- `/home/pikdum/.cache/thistle-wow-playtest.WLUq0e/screenshots/` (observer).
- `/home/pikdum/.cache/thistle-wow-playtest.VFLFgg/screenshots/` (subject).
- `/tmp/thistle-invisibility-server-final.log`.
- `/tmp/thistle-invisibility-{hidden,detected,cancellation-fixed,potion-expiry,aggro-hidden,aggro-revealed,melee-break}.txt`.

## Automated validation

Pure tests cover type matching, strength, shared types, world bosses,
drunkenness, collision distance, weaker-effect fallback, glow cleanup,
expiry, death, and interruption. Boundary tests cover visibility changes,
queued-update filtering, aggro probes, targeting rejection, and client aura
cancellation. Tagged loader tests check actual potion and warlock spells.

The initial full run had one database-preload timeout while two software-rendered
clients were starting. With that contention removed, the full suite passed.
After the cancellation fix and missing-perception guard:

- `mix test.all`: 2,960 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- `git diff --check`: passed.

Logs: `/tmp/thistle-invisibility-{all,compile,credo}-final.log`.
