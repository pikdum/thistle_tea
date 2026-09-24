# Buff ranks and recipient levels

Ranked positive buffs now observe vanilla's ten-level allowance. Direct
player casts select the highest eligible ancestor of the requested rank,
even when that lower rank is not in the spellbook. Validation, cost,
effects, and launch packets use the selected rank; cast results retain the
client's requested spell ID. An explicit target below every rank receives
`LOWLEVEL` before resources are spent. The launch boundary rechecks the
target's current level.

Ordinary group buffs exclude ineligible secondary recipients, checking
each pet's own level. Persistent party auras select a rank independently
at each recipient and keep the caster's rank. Refresh, rank replacement,
and expiry use the existing aura transitions and derived-stat recompute.
Item casts, triggered casts, creature casters, and the explicit low-level
buff attribute retain their corresponding validation exceptions.

Spell metadata now retains the previous rank. SkillLineAbility successor
links supply cached fallback chains for spells such as Devotion Aura,
whose chain is absent from the explicit VMangos table. Explicit chains
take precedence; cyclic fallback chains are discarded. The fallback is
preloaded at startup, before other world loaders consume spell metadata.

## References and automated validation

- `refs/vmangos/src/game/Spells/SpellMgr.cpp`: `SelectAuraRankForLevel`
  and skill-ability chain construction in `LoadSpellChains`.
- `refs/vmangos/src/game/Handlers/SpellHandler.cpp`: direct-cast rank
  selection and the original spell pointer.
- `refs/vmangos/src/game/Spells/Spell.cpp`: `SendCastResult`, `CheckCast`,
  and secondary recipient checks in `CheckTarget`.
- `refs/vmangos/src/game/Spells/SpellAuras.cpp`: party-area aura rank
  selection for each recipient.

Implementation `5e7c878b` passed `mix test.all` (5,631 tests),
`mix compile --warnings-as-errors`, `mix credo --strict` (zero issues),
formatting, and whitespace checks. Eighteen added tests cover boundaries,
exemptions, mixed effects, chain loading and cycles, unlearned lower ranks,
costs, actual-rank delivery and launch events, original-ID results and
cancellation, launch revalidation, self casts, recipient refresh,
replacement, expiry, explicit-chain precedence, and real DBC ranks.
Existing party targeting tests also cover pets independently of owners
and item/triggered/continuous-aura exceptions.

## Native client acceptance

A fresh server on the implementation commit served two isolated
build-5875 clients. Native input performed setup and gameplay; Tidewave
only read state. WoW PIDs 188377 and 189298 each had active amdgpu counters.

Debugpriest (GUID 4, level 60) cast Power Word: Fortitude rank 6 (`10938`)
on Debugbuyer (GUID 10, level 1). The client displayed “Increases Stamina
by 3”; owner state held only rank 1 (`1243`), stamina changed from 112 to
115, and the priest's mana changed from 1,770 to 1,710 at application.
The priest had god mode off throughout. A training mob interrupted the
initial setup, so the recipient was resurrected and moved away from the
seeded combat area. Recipient god mode was on for this first buff trial
and off for all following trials.

At level 2, another rank-6 request replaced rank 1 with rank 2 (`1244`).
The recipient's tooltip showed +8 stamina and owner stamina was 121.
The exact level-2 boundary and absence of a duplicate Fortitude holder
were confirmed.

Prayer of Fortitude rank 2 (`21564`) against that target returned the
visible “Target is too low level” error. Mana remained at 4,411 and all
five Sacred Candles remained. After grouping, the priest targeted herself
and cast the same Prayer: stamina rose from 87 to 141, the Prayer holder
was `21564`, and candles fell to four. The nearby level-2 member retained
only direct Fortitude `1244`, with stamina still 121.

Debugpaladin (GUID 2, level 60) then grouped with Debugbuyer and cast
Devotion Aura rank 7 (`10293`). Both had god mode off. The caster's tooltip
showed +735 armor and armor changed from 5,249 to 5,984. The level-2 member
received rank 2 (`10290`): tooltip +160 armor, owner armor 5,001 to 5,161.
The caster retained a permanent holder; the member received the ordinary
short recipient expiry refreshed by party-aura pulses.

Moving the member outside the aura radius removed `10290` and restored
armor to 5,001. A 20 ms sampler recorded the move at 2,414 ms and removal
at 4,102 ms, a 1,688 ms delay within the existing 2.5-second expiry.
Returning in range restored rank 2. Raising the member to level 10 changed
the recipient rank on the next pulse, 604 ms later: one holder `643`,
tooltip +275 armor, and armor 5,286. The previous rank did not stack.

Leaving the party removed rank 3 after 2,288 ms and restored the new
level-10 armor baseline of 5,011. The paladin cancelled the source aura
through the client. Final reads found both players alive, ungrouped, with
god mode off, no Devotion holder, and baseline armor. Screenshots confirm
the rank-specific tooltips and disappearance on range and party changes.

The only spell-validation warning was the intentional Prayer `LOWLEVEL`
rejection. No server errors, unsupported actions, or owner crashes were
observed. Both helper-owned client cgroups and the retained server were
stopped; player owners and metadata were absent after client shutdown.

## Retained evidence

- Caster session: `/home/pikdum/.cache/thistle-wow-playtest.E6Wg12/`.
- Recipient session: `/home/pikdum/.cache/thistle-wow-playtest.V8reMl/`.
- Direct casts: `/tmp/thistle-aura-rank-fortitude.txt` and
  `/tmp/thistle-aura-rank-level-two.txt`.
- Prayer: `/tmp/thistle-aura-rank-prayer-{rejected,party}.txt`.
- Devotion: `/tmp/thistle-aura-rank-devotion-{before,after}.txt`.
- Lifecycle traces: `/tmp/thistle-aura-rank-{range,level-refresh,leave-party}.txt`.
- Cleanup: `/tmp/thistle-aura-rank-{final-state,stopped-owners}.txt`.
- GPU counters: `/tmp/thistle-aura-rank-gpu.txt`.
- Server log: `/tmp/thistle-aura-rank-server.log`.
- Gates: `/tmp/thistle-aura-rank-{all,credo}.log`.
