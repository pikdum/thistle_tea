# Battleground insignia acceptance

Native build-5875 acceptance on 2026-09-23 used fresh local servers and isolated
GPU clients. Behavioral references were VMangos `Player::RemovedInsignia`,
`Player::SendLoot`, `Spell::EffectSkinPlayerCorpse`, `Spell::EffectSpiritHeal`,
`Player::BuildPlayerRepop`, and `Map::ConvertCorpseToBones`.

## Implementation

Remove Insignia (22027, effect 116) uses the normal spell pipeline, with separate
body admission at cast start, launch, and claim. Pure rules check opposing teams,
life state, body availability, world identity, visibility, line of sight, and
the DBC spell's ten-yard range. The victim owner serializes forced release with
resurrection; the corpse owner serializes competing claims and gold collection.

Released corpses retain the victim's team, level, death identity, and faction
projection, so removal also works after logout. Conversion creates independently
identified bones, preserving them across the victim's resurrection and later
deaths. Money is rolled once with the Vanilla level formula and uses the existing
loot session. Only the initial remover's automatic loot view uses spell range;
ordinary views and money collection retain the normal five-yard limit. Bones
expire after sixty minutes and are removed during world teardown.

Enemy and ally corpse target masks now decode their GUIDs before location fields,
matching the client wire order. The new `SMSG_PLAYER_SKINNED` codec tells an online
victim that only graveyard resurrection remains. The gameplay implementation
adds no runtime database queries or architecture allowlist entries.

## Native results

Level-50 Debugmage (Alliance, GUID 5) and Debugshaman (Horde, GUID 8) entered
Arathi Basin through `.bg join arathi` and **Enter Battle**, sharing map 529,
instance 1. `.bg start` shortened preparation; `.die` supplied the deaths.
Looting, release, cancellation, resurrection, and reconnect used client actions.

| Check | Observed result |
| --- | --- |
| Unreleased enemy | Right-click sent Remove Insignia, forced the shaman to the Horde graveyard as a ghost, displayed “Insignia Taken - You can only resurrect at the graveyard,” and opened 483 copper for the mage. |
| Cancellation | Clicking the resurrection dialog's Cancel button removed the waiting aura and emptied the match queue. The shaman remained a ghost beyond a subsequent wave. |
| Requeue | Right-clicking the Horde Spirit Guide reapplied Waiting to Resurrect (2584), queued GUID 8, and restored 2415 health at the normal wave. The waiting aura disappeared. |
| Retained bones | The first bones remained after resurrection and subsequent deaths. Clicking the money icon changed mage coinage from 100000000 to 100000483 and left zero gold on the bones. |
| Released enemy | A later released body accepted the enemy-corpse target packet and opened 472 copper. The original corpse disappeared and the online victim's reclaim timestamp became nil. Collection produced a total of 100000955 copper. |
| Offline victim | On the final source revision, the shaman logged out before removal. The mage still cast Remove Insignia on the released body and received a 351-copper loot window; the original corpse owner was gone and the player owner was absent. |
| Reconnect | After offline removal, the shaman re-entered the same match with health 1, ghost state true, and no original corpse. A subsequent ordinary resurrection wave restored full health. |
| Cleanup | Both players left for their original Programmer Isle coordinates. Match lookup, bones positions, and bones metadata returned nil. |

Playtesting exposed two lifecycle defects that were fixed before completion.
Cancellation previously left a player queued for resurrection. Removing the
waiting aura now emits queue cancellation, and the player owner rejects a wave
if the aura is absent. Login previously resurrected any ghost whose corpse was
missing. Corpse restoration now preserves ghosts in an active battleground,
including bodies removed while their owners were offline; ordinary missing-body
recovery outside battlegrounds remains covered by tests.

One debug teleport used a coordinate below the local ground and was discarded.
The repeated setup teleported above the terrain at `1167.2 1197.5 -54` and waited
for the client to settle at z `-56.3705` before death. Early clicks made before a
resurrection dialog appeared are not cancellation evidence. The ten-yard initial
view exception, concurrent claims, stale death rejection, other-copy rejection,
and timed expiry are automated evidence, not additional native claims.

## Evidence and validation

- Main acceptance clients: Alliance
  `/home/pikdum/.cache/thistle-wow-playtest.jc5azS`, Horde
  `/home/pikdum/.cache/thistle-wow-playtest.96VfKG`.
- Final reconnect clients: Alliance
  `/home/pikdum/.cache/thistle-wow-playtest.fYOev5`, Horde
  `/home/pikdum/.cache/thistle-wow-playtest.AxRdEs`.
- Main screenshots: `removed-unreleased`, `canceled-resurrection`, `requeued`,
  `normal-wave`, `corpse-hover`, and `logout` in the respective session folders.
- Final screenshots: Alliance `offline-corpse` and `offline-loot`; Horde
  `reconnected-after-offline-removal`.
- Logs: `/tmp/thistle-insignia-fixed-server.log` and
  `/tmp/thistle-insignia-reconnect-server.log`.
- Final clients used the RX 7900 XT at PCI `0000:0c:00.0`. WoW's own gfx counters
  advanced from 1366867841 to 18326341281 ns (PID 2301359), and from 372947693 to
  14207713353 ns (PID 2302162).

The logs contain the expected duplicate-character rejection during second-client
selection and existing unsupported account-data, raid-info, ticket, and meeting
stone requests. No insignia, corpse-loot, owner, or visibility failures occurred.
All helper-owned clients and retained server PTYs were stopped; evidence remains.

Validation: `mix test.all` passes 5213 tests; `mix compile --warnings-as-errors`,
`mix credo --strict`, formatting, and `git diff --check` pass. New integration
tests use mutually exclusive DBC or map tags; default tests use fixtures.
