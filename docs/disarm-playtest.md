# Main-hand disarm

Disarm previously set the client flag and multiplied all melee damage by 0.5.
It now distinguishes equipped player weapons, natural feral attacks, and
armed creatures.

- Players use a two-second unarmed swing with base damage 1–2 plus their
  current attack-power contribution. Equipped weapon inputs remain intact.
- Armed creatures deal 40% of their normal main-hand damage without changing
  their swing speed. Unarmed creatures retain their normal damage.
- Off-hand damage, timing, and weapon skill remain independent. Ranged weapons,
  including magic-classified wand shooting, remain usable.
- Weapon-dependent melee abilities fail while disarmed. Casts preparing when
  Disarm lands are checked again at launch. Queued next-swing weapon abilities
  fail without spending their resource cost, then produce an ordinary punch.
- Allowed melee abilities snapshot unarmed damage and skill. A player without
  an off-hand weapon cannot parry while disarmed; the client parry percentage
  is recomputed through the aura transition.
- Expiry, removal, overlapping auras, death, and form changes reuse the aura
  lifecycle and stat recomputation. No stale weapon or attack-power snapshot
  is restored.

The reference behaviors are `Aura::HandleAuraModDisarm`,
`Player::CalculateMinMaxDamage`, `Creature::UpdateDamagePhysical`,
`Unit::CanUseEquippedWeapon`, `Player::GetWeaponForParry`, and
`Spell::CheckItems` in `refs/vmangos/src/game/`.

## Regressions covered

Focused tests exercise damage and speed, off-hand preservation, independent
attack skills, overlapping aura expiry, changed canonical weapon inputs,
current attack power, feral forms, death cleanup, creature weapon presence,
cast and queued-swing rejection, unarmed spell snapshots, parry restoration,
wand eligibility, and the serialized equipment-error packet.

The queued-swing, off-hand skill, and parry gaps were found while connecting
the system to existing combat paths and fixed as part of this work.

## Real-client acceptance

Two isolated build-5875 clients used level-50 Debugwarrior (GUID 1) and
Debugshaman (GUID 8). The shaman learned NPC Disarm 6713 through `.learn` and
cast it through the normal client spell path during a duel on Programmer Isle.
Read-only owner samples accompanied screenshots and real melee exchanges.

- The armed warrior had damage 112.4–159.4, a 2,100 ms swing, and 5% parry.
- Disarm changed those to 57.5714–58.5714, 2,000 ms, and 0% parry. The client
  displayed the debuff, unarmed damage, and the main-hand weapon requirement
  error when attempting Heroic Strike.
- During a landed Disarm, actual swings removed 28 and 29 health from the
  armored opponent. After expiry, ordinary hits again removed roughly 58–67
  health. The original damage range, swing speed, and parry percentage returned.
- A subsequent application also restored correctly. The sampled durations
  were approximately six and three seconds through existing diminishing returns.
- Heroic Strike was accepted again after an expired application. Missed or
  avoided Disarm casts were retried rather than counted as successful tests.
- In Stranglethorn Vale, the shaman cast Disarm on a level-43 Bloodsail
  Swashbuckler (entry 1563, spawn 2575) wielding a sword. Its authoritative
  outgoing damage changed from 66.576814–88.252986 to
  26.6307256–35.3011944, exactly 40%, while its swing stayed at 2,000 ms.
  The client showed the debuff; after six seconds, the original damage
  returned. The timeline is `/tmp/thistle-disarm-armed-creature-timeline.txt`.

The initial outdoor creature check exposed a map-transfer crash:
`UpdateBatcher` could drain an out-of-range block into a mixed update list,
but `UpdateObject.packet_body/2` only encoded values and creates. The codec
now handles removals in either single or batched packets, including the
transport header. The player packet boundary also applies tracking changes
in wire order, so queued removals cannot leave stale tracked entities and a
later recreate is retained. Dedicated regressions cover all three cases.
After loading the corrected codec and packet boundary, the shaman rejoined
the outdoor area, completed the creature test, and returned to Programmer
Isle without another owner or connection failure.
A further round trip repeated the original transfer successfully. The final
owner was alive on map 451 with eight tracked entities; its sample is retained
in `/tmp/thistle-disarm-transfer-fixed.txt`.

## Validation and evidence

- `mix test.all`: 2,977 passed after the visibility fix.
- `mix compile --warnings-as-errors`: passed.
- Strict Credo and formatting hooks: passed.
- `git diff --check`: passed.

Screenshots are retained in
`/home/pikdum/.cache/thistle-wow-playtest.tnK5Vs/screenshots/` (warrior) and
`/home/pikdum/.cache/thistle-wow-playtest.H5wCuU/screenshots/` (shaman).
The landed duel timeline is `/tmp/thistle-disarm-final-duel-retry.txt`.
Validation logs are `/tmp/thistle-disarm-{all,compile,credo}-final.log`;
the playtest server log is `/tmp/thistle-disarm-server-final.log`.
