# Creature targets for quest tools

On-use items now enforce the creature entry and living/dead requirements in
`item_required_target`. Multiple rows are alternatives. Invalid selections
report `bad_targets` before casting, charge consumption, or cooldown activation;
the inventory failure acknowledgement also releases the client's item lock.
Items without rows retain their existing behavior.

The boundary preloads the current 37 valid bindings into ETS. The loader checks
item and creature existence and accepts target types 1 and 2. Gameplay uses the
cache and a pure target predicate, with no per-use database query. The current
rows have explicit on-use targets and no `spell_script_target` overlap; the
reference loader's extra checks for those cases are not implemented here.

DBC `ALLOW_DEAD_TARGET` now survives loading, cast validation, recipient
selection, and cast delivery. The flag permits corpse script effects while
ordinary damage, healing, and aura effects remain filtered from dead targets.
The Muisek capture spells and Summon Screecher Spirit request corpse removal
after one second through the existing owner-local despawn/respawn lifecycle.
Caster rewards remain separate from corpse effects.

Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Item::IsTargetValidForItemUse`, `WorldSession::HandleUseItemOpcode`,
`ObjectMgr::LoadItemRequiredTarget`, `SpellEntry::CanTargetDeadTarget`, and
the capture cases in `Spell::EffectDummy`.

Implementation commits:

- `d15d6532 feat(items): enforce creature targets for quest tools`
- `5376ad36 fix(spells): preserve hostile corpse effects during cast delivery`

## Native acceptance

Build-5875 GPU clients used Debugmage, GUID 5, at level 50. Existing `.additem`,
`.go xyz`, and `.tgm` commands supplied setup. Combat and item uses went through
native client input; Tidewave supplied read-only observations.

1. Super Snapper FX, item 9328, rejected a living Wandering Forest Walker,
   entry 7584. The client displayed `Invalid target`; the server logged spell
   11610 failing with `bad_targets`. No snapshot, charge, or cooldown appeared.
2. Treant Muisek Vessel, item 9606, rejected that same living creature.
   Spell 11885 reported `bad_targets`; the vessel remained and no Muisek or
   cooldown appeared. Both cases were repeated after the final code change.
3. Native Frostbolt, Fireball, and Fire Blast killed the walker. Voodoo Charm,
   item 8149, rejected the dead walker because its entry was wrong for spell
   10617. Its count remained one and its single consumable charge remained
   `-1`, with no cooldown or reward.
4. The vessel accepted the dead walker. The client displayed
   `You create: [Treant Muisek]`; the owner gained one item 9593, retained the
   vessel, and recorded its cooldown. A 50 ms sampler observed the reward at
   5,237 ms and corpse removal at 6,210 ms. Removal cleared the world position
   and marked the corpse removed while retaining the owner and respawn timer.
   The client lost the corpse target after the delayed removal.
5. The camera accepted living Gammerita, entry 7977, spawn 93683, near
   `{-28, -4670, 10.3}` on map 0. The client displayed
   `You create: [Snapshot of Gammerita]`; item 9330 increased from zero to one,
   the reusable camera remained, and its cooldown activated.
6. Logout removed the player owner, metadata, and world position. The runtime
   character store retained one each of items 8149, 9328, 9330, 9593, and 9606.
   Reconnecting created a new owner with the same five item instances and the
   charm's unused charge. Final logout again removed all player projections.

The accepted corpse was walker spawn 50797, GUID 17379391089261201005, near
`{-3503.47, 2660.11, 89.30}` on map 1. These native cases exercise representative
living/dead restrictions; all 37 bindings were not individually playtested.

## Regression and checks

The first native capture created its caster reward but left the corpse behind.
Cast delivery recalculated `target_hostile?` without the spell's corpse flag,
so recipient filtering silently discarded the enemy-target dummy effect.
The new cast-completion regression failed with an empty corpse effect list
before the fix, then passed with the delayed despawn and separate caster reward.

- `mix test.all`: 6,854 passed in 77.7 seconds after the final code edit.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues; commit formatting checks passed.

Coverage includes alternative creature entries, life state, missing target
facts, invalid-use feedback, charge/cooldown preservation, corrected retries,
real VMangos bindings, real DBC corpse flags, normal-spell restrictions, and
the complete cast-to-corpse effect path.

Runtime and checks used
`NAMIGATOR_SRC=/nix/store/3nds85i5fyjgpqcgjnk03fdfgs798vfn-namigator-with-wmo-metadata`.

## Evidence and cleanup

Final successful capture, camera, and reconnect screenshots are under
`/home/pikdum/.cache/thistle-wow-playtest.7gqnWx/screenshots/`:
`wrong-corpse-rejected.png`, `capture-result.png`, `corpse-removed.png`,
`camera-success.png`, `logged-out.png`, and `reconnected-items.png`.
Living-target rejection screenshots are `fresh-rejected-9606.png` and
`fresh-rejected-9328.png` in the earlier helper session
`/home/pikdum/.cache/thistle-wow-playtest.fqJRLg/screenshots/`.

Evidence files use the prefix `/tmp/thistle-item-targets-`:
`final-server.log`, `final-warnings.txt`, `fresh-rejections.txt`,
`clean-rejected.txt`, `clean-watch.txt`, `clean-captured.txt`,
`clean-camera.txt`, `clean-logout.txt`, `clean-reconnected.txt`,
`clean-final-logout.txt`, `final-all.log`, `final-compile.log`, and
`final-credo.log`.

Preliminary attempts included a patrolling target moving out of range, an
invalid vanilla `/cleartarget` command, and a teleport below terrain. The
reused client also reported range failures before sending item packets after
the server restart; even character reconnect did not resolve those attempts.
The accepted capture used a newly launched helper process. The cause of those
earlier client range discrepancies was not established, and no movement fix
is claimed. Initial probe expressions with invalid fields were discarded.
An attempted development hot reload briefly made `Casting` unavailable to
an unrelated mob; the server was restarted before final acceptance.

The final server log contains no errors. Warnings consist of the three
intentional `bad_targets` rejections and existing unsupported account-data and
GM-ticket requests. WoW PID 2009067 used `amdgpu`; its own graphics counter
increased from 3,298,597,575 to 17,681,064,382 ns. The earlier WoW PID 1986695
also used hardware rendering.

Both helper services were stopped through their recorded invocations
(`145d1414716c4b3b9f83858bacb56c06` and
`7312336d759c422896562834ebb2c855`). Both became inactive with empty cgroups,
both WoW PIDs disappeared, and both retained server PTYs exited. Ports 4000,
3724, and 8085 were free. Artifacts were retained.
