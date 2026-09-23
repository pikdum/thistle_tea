# Readable and interactive quest objects

Validated on 2026-09-23 with the native build-5875 client and a fresh local server.
The fixtures use unchanged VMangos templates on Programmer Isle. Interaction goes
through mouse clicks, the client's Opening spell, and ordinary quest UI.

## Shared behavior

- Type 9 world text and type 10 interactive quest objects use the page-text packet
  and preloaded page chains. Page display precedes the quest requirement; page
  text takes precedence over gossip.
- Player state owns quest eligibility, credit, mount/aura preparation, and menus.
  The object owner serializes admission, activation, scripts, linked traps, spell
  delivery, and revision-checked reset or consumption.
- Accepted use credits nearby eligible party members' shareable quests. Rejected
  or repeated active use grants no credit. Quest highlighting is projected for
  each viewer and refreshes with their quest log.
- Consumable database spawns use their respawn delay. Their replacement has fresh
  activation state. Script lookup and condition metadata preserve database spawn
  identity when runtime GUIDs change in an instance.
- Game-object objective notifications set the client's `0x80000000` entry marker.
  This fixes the existing creature-only encoding of object progress.
- Opening a quest object's lock does not trigger its linked trap until the
  subsequent quest-object admission succeeds.

## Native evidence

The retained sessions are under `/home/pikdum/.cache/`:

- `thistle-wow-playtest.jMHQVN`: Eliza's Tombstone opens with stone page styling.
  Accepting quest 953 from Sentinel Tysha Moonblade enables the Ameth'Aran
  plaques. Each plaque opens its page chain; Next advances to page 2. Both reads
  produce authoritative counts `%{0 => 1, 1 => 1}` and `:complete`, and the quest
  log displays both objectives as 1/1 Complete. The human debug character sees
  the plaques' assigned language rendered as unreadable text, as expected.
- `thistle-wow-playtest.sszBlo`: repeats plaque use with the corrected objective
  packet. Silithyst Geyser visibly disappears after use. A read-only sampler
  observes ready state 1, active state 0, then no owner, position, or metadata.
  This validates consumption, not the separate Silithus PvP carrier script.
- `thistle-wow-playtest.CoJBb5`: Cleansed Songflower applies spell 15366. The
  client displays its 60-minute buff; intellect increases from 195 to 210. The
  holder's caster is the flower GUID, and the object returns to ready state.
  Logout removes the player owner while retaining the holder in CharacterStore;
  reconnect displays the buff again with the same caster and 210 intellect.

GPU rendering was checked on the RX 7900 XT, including WoW's own `amdgpu` DRM
engine counters. Server logs are retained as
`/tmp/thistle-quest-objects-{server,final-server,acceptance-server}.log` and the
consumption sampler as `/tmp/thistle-goober-geyser-probe.log`.

No owner crashes or interaction errors occurred in these paths. Login still
reports the existing unsupported account-data, raid-info, GM-ticket, and
meeting-stone messages.

All three helper-owned services and their servers were stopped after acceptance.

## Reproduction

Start the development server and use the project client-playtest helper. The
fresh Debugmage has no quest 953 or Songflower buff.

1. `.go xyz 16320.2 16348.1 70.0 451`, then right-click Eliza's Tombstone.
2. `.go xyz 16320.2 16354.1 70.0`, then accept quest 953 from the Sentinel.
3. Use the plaques from `{16325.2, 16348.1, 70.0}` and
   `{16330.2, 16348.1, 70.0}`. Wait for Opening to finish. Check page navigation,
   quest progress, completion, and the restored object state.
4. `.go xyz 16335.2 16360.1 73.0`, then use Cleansed Songflower. Check the buff,
   derived stats, object reset, and reconnect retention.
5. `.go xyz 16340.2 16360.1 73.0`, then use Silithyst Geyser and check removal.

The last two fixtures sit on rising terrain; teleport above the ground instead
of reusing the flat plaza's 69.44 height.

Automated tests cover failed quest requirements, cooldowns, repeated use, custom
animations, stale timers, spell attribution and world changes, gossip selection,
party credit, per-viewer flags, instance script identity, cache decoding, packet
encoding, and consumed-spawn cleanup and replacement.

Final validation: `mix test.all` passed 5,158 tests; compilation with warnings as
errors, strict Credo, formatting, and `git diff --check` passed. The final suite
ran alone after all playtest processes had stopped.
