# Gathering and object locks

Build 5875, September 21, 2026. Implementation commits:

- `bdf9899f`: cached lock requirements and shared gathering rules.
- `a48d01ca`: object admission, resource harvests, costs, and loot lifecycle.
- `f46df2c3`: deferred success feedback and abandoned-loot cleanup.

The final implementation passes all 4,161 tests through `mix test.all`,
compilation with warnings as errors, strict Credo, and formatting. The
architecture dependency allowlist is unchanged. Repository edits, builds,
tests, and commit hooks ran with the playtest server and client stopped.

## Shared behavior

The startup loader caches all eight ordered alternatives in each Lock DBC
row. Pure resolution supports item keys, lock types, effective profession
skills, and spell-provided opening strength. Item casts use their item and
spell strength rather than the player's skill, and award no skill gain.
Mining, Herbalism, and Lockpicking use the same opening rules; Skinning
shares the gathering skill-gain calculation.

Pre-cast validation and completion use the cached catalog. Completion
rechecks the living player, target visibility, world, distance, line of
sight, skill, tools, and cast-item ownership. The object owner serializes
admission, rejects concurrent access, rolls gathering failure, and records
at most one successful skill gain per player per spawn. Direct object use
and loot requests cannot bypass resource locks. Reagents and item charges
are planned together and committed only after admission succeeds.

Partially collected loot survives closing, movement away, logout, and
reopening. Loot access is released on death, unavailable targets, normal
logout, and abrupt looter-process termination. Process monitors belong to
the object owner and are removed when access closes. Reopening existing
loot does not count as another harvest or duplicate an awarded skill gain.

Veins use their template's minimum and maximum harvest counts and the
VMangos replenishment probability. Each new harvest requires another
successful cast. Exhaustion removes the object from world presence and
visibility; respawn resets harvest count, access, and skill-gain history.
Herbs use a single harvest. Existing spawn-pool recycling remains in use.

Object-opening success packets and quest cast credit are deferred until
the object accepts the attempt. Rejection uses the shared full spell-failure
projection so the native client can retry.

References: local VMangos `Spells/Spell.cpp` (`CanOpenLock` and finished-cast
checks), `Spells/SpellEffects.cpp` (`EffectOpenLock`), `Objects/Player.cpp`
(`UpdateGatherSkill`), `Handlers/LootHandler.cpp` resource replenishment,
and `Objects/GameObjectDefines.h` lock and harvest fields.

## Client acceptance

Debugwarrior (GUID 1) used two fresh servers and isolated Wine/Xvfb client
sessions. The first ran `a48d01ca` and exposed the retry bug below. The final
run used `f46df2c3`, native trainer dialogs, right-click gathering and loot
controls, and logout/reconnect. The client was restricted to CPU cores 0–3.
Tidewave probes read selected live owner and CharacterStore fields without
mutating gameplay state.

Teleports positioned the character at trainers and active resource nodes.
`.additem 2901 1` supplied a Mining Pick after testing the missing-tool
message. Mining and Herbalism were learned from Gelman Stonehand and
Shylamiir; skills were not raised with debug commands.

| Transition | Client and authoritative result |
| --- | --- |
| Try Mining without a pick | Native “Requires Mining Pick” message; no loot or progress |
| First attempt with a pick | Native “Failed attempt”; no loot, access, harvest use, or skill gain |
| Retry the same vein | New Mining cast succeeds; native Mining 1-to-2 notification and Copper Ore/Rough Stone loot |
| Close and reopen without looting | Identical contents remain; Mining stays at 2 and harvest count stays at zero |
| Collect successive harvests | Four separate successful harvests yield four Copper Ore and three Rough Stone; failed attempts between harvests remain retryable; Mining stays at 2 |
| Exhaust the vein | Harvest count reaches four; presence is removed, access and monitors clear, and returning to the site shows the vein gone |
| Gather Silverleaf | Herbalism advances from 1 to 2; three Silverleaf appear in the loot window |
| Logout with herb loot still open | Player owner exits; node viewers, access, and monitors clear; the same three herbs remain unclaimed |
| Reconnect and gather that plant again | Same three herbs reopen; Herbalism remains at 2 |
| Collect the herbs | Client plant disappears; server records one harvest and removes its presence |
| Final logout/reconnect | Owner and CharacterStore retain Mining 2/75 and Herbalism 2/75; inventory retains four Copper Ore, three Silverleaf, and the pick; no active cast or loot window |

The final vein was entry 1731, DB GUID 26768, at
`{-9101.61, 76.0012, 93.6697}` on map 0. The herb was entry 1617 at
`{-9144.78, 97.4556, 74.8526}`. Active nodes are pool-selected, so a fresh
server may choose different spawns.

Automated coverage additionally checks ordered key/skill alternatives,
skill bonuses and item strength, Lockpicking and high-skill failure rules,
skill-gain thresholds, direct-loot bypass, concurrent admission, stale or
dead targets, changed tools/skills, transactional item charges, settlement
of an earlier item-loot window, abrupt process death, independent player
gain history, replenishment bounds, and respawn reset. Lockpicking/key
opening and timed pool respawn were not separately exercised in the native
client during this run. Inventory lockboxes and trade-slot unlocking are
outside this implementation.

## Bug found and corrected

The first run sent spell-success feedback before the object rolled the
gathering attempt. After a failure, the client displayed “That is already
being used” and stopped sending new casts even though the server node was
free. Deferring success and sending the complete failure response fixed the
retry path. The final run demonstrated failure followed by successful retry
both before the first harvest and between later harvests.

The final server log contains no gameplay errors. Its warnings are the
existing unsupported login/account requests: `CMSG_UPDATE_ACCOUNT_DATA`,
`CMSG_REQUEST_RAID_INFO`, `CMSG_GMTICKET_GETTICKET`, and
`CMSG_MEETINGSTONE_INFO`. Both clients and servers were stopped afterward.

Evidence is retained locally in
`/home/pikdum/.cache/thistle-wow-playtest.KviB1Y` and
`/home/pikdum/.cache/thistle-wow-playtest.9M8m4p`. Final screenshots include
`mining-attempt-1`, `mining-attempt-2`, `mining-reopen`,
`mining-harvest-2-retry`, `copper-site-after-exhaustion`, `silverleaf-loot`,
`silverleaf-exhausted`, and `gathering-final-inventory`. Logs are
`/tmp/thistle-gathering-server-2.log`,
`/tmp/thistle-gathering-final-reconnect.log`,
`/tmp/thistle-gathering-fixes-test-all.log`,
`/tmp/thistle-gathering-fixes-compile.log`, and
`/tmp/thistle-gathering-fixes-credo.log`.
