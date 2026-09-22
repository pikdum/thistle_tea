# Noncombat critter companions

Implemented in `f1c703c3`, with placement and helpful-spell immunity refined in
`355586cc`. Automated and native acceptance completed on 2026-09-22.

## Behavior and reference

DBC effect 97 now summons a noncombat pet through a typed owner-local request.
All 100 current critter-summoning spells load with this semantic. A separate
mini-pet identity leaves the combat companion, summon field, and pet controls
intact. Using the same critter again dismisses it; another critter replaces it.

Critters retain their creature template's level, health, appearance, NPC flags,
and creation passives. They inherit the owner's faction, carry player/NPC
immunity flags, and have no combat action bar or loot. Shared target validation
now respects those immunity flags, including immunity to helpful player spells.

Destination summons appear beside the caster and face the owner. A passive
behavior tree follows behind the owner through the existing navigation system.
Death, logout, world transitions, missing owner presence, excessive distance,
or a positive spell duration ending remove the critter. Actor monitoring clears
only the matching identity, so stale removal cannot clear a replacement.
Critters are not restored on reconnect or map changes.

The Disgusting Oozeling's creation passive uses the existing area-aura system.
It refreshes the owner's resistance and Defense penalties without starting
combat; the penalties expire after the critter stops refreshing them.

Reference: `refs/vmangos` at `8f4e60845`, specifically
`Spell::EffectSummonCritter`, mini-pet creation/update/removal in `Pet.cpp`,
`Player::RemoveMiniPet`, and the player/NPC immunity checks in `Unit.cpp`.
The shared summoning and lifetime system does not add individual critter scripts.

## Automated acceptance

`mix test.all` passed **4,651 tests**. `mix compile --warnings-as-errors` passed,
and `mix credo --strict` found zero issues across 1,819 source files.
The architecture ratchet passed without an allowlist change.

Coverage includes all 100 DBC mappings and caster resolution, explicit owner
delivery, coexistence, toggle/replacement, stale monitor messages, immunity
categories, placement, following, missing/dead/distant/other-world owners,
actual actor duration expiry, death/worldport cleanup, and the Oozeling's
creation passive and expiry. Generated DBC tests use the `:dbc_db` tag; actor
lifecycle tests use cached synthetic creature templates.

## Native client acceptance

An isolated build-5875 client used Debugwarlock (GUID 6), level 60, on a fresh
server. Existing development commands supplied levels, items, map travel, and
the final lethal transition. Summon Imp, critter item use, item-binding
confirmation, walking, targeting, logout, and reconnect used native client
actions. Tidewave probes only read state.

| Item | Summon spell | Creature | Observed level |
| --- | --- | --- | --- |
| Mechanical Squirrel Box (4401) | 4055 | 2671 | 15 |
| Rabbit Crate (Snowshoe) (8497) | 10711 | 7560 | 1 |
| Disgusting Oozeling (20769) | 25162 | 15429 | 5 |

- In Goldshire, each item summoned the correct visible, named model while the
  Imp remained present. The Imp's GUID `17383894568633631273` and native pet bar
  stayed unchanged through critter toggles and replacements.
- Walking roughly 19 yards moved the squirrel with its owner. Native targeting
  displayed its name, level, and ownership label. The owner and both pets stayed
  out of combat.
- Reusing the squirrel item removed it. Summoning a rabbit replaced a new
  squirrel, and summoning an Oozeling replaced the rabbit. Each old GUID lost
  its actor, world position, and metadata.
- The Oozeling displayed its debuff and tooltip, and tinted the character green.
  Fire resistance changed from 22 to 2, nature/shadow resistance from 0 to -20,
  and Defense gained a -20 modifier. Dismissal removed the aura and restored
  these values. No combat state was created.
- Moving from map 0 to Programmer Isle (451) removed a second Oozeling and its
  aura. The combat Imp restored through its existing lifecycle; the critter did
  not return.
- A new rabbit disappeared on native logout. Reentering the same character
  restored the Imp with no mini pet or mini-pet monitor.
- After summoning another rabbit, `.die` entered the shared lethal transition.
  The native death dialog appeared, both pets disappeared, health reached zero,
  both companion slots cleared, and the mini-pet monitor cleared. Both final
  actor GUIDs had no process, world position, or metadata.

The session was `thistle-wow-playtest.nK2voE`. Screenshots remain in its
`screenshots/` directory, including `squirrel-summoned.png`, `squirrel-follow.png`,
`rabbit-replacement.png`, `oozeling-aura.png`, `oozeling-aura-gone.png`,
`after-worldport.png`, `logged-out.png`, `reconnected.png`, and `owner-death.png`.
Read-only probes, snapshots, and the server log remain under `/tmp/thistle-mini-*`.

The server log contained no errors or summon failures. Existing login warnings
remained for account-data updates, raid-info requests, GM tickets, and
meeting-stone information. The helper-owned client, X server, and game server
were stopped. A second native observer client was not used.
