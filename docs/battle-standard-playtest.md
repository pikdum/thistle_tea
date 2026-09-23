# Independent wards and battle standards acceptance

Build-5875 acceptance on 2026-09-23 used fresh local servers and three isolated
GPU clients. Behavioral references were VMangos `Spell::EffectSummonTotem`,
`Totem.cpp`, the totem branch in `AreaAura`, and battleground spell admission in
`SpellMgr.cpp`.

## Implementation

Spell effect 74 now uses the shared totem pipeline without occupying an elemental
slot. Each independent ward has its own GUID key, while effects 87–90 retain slot
replacement. The caster owns tracking, and both players and creatures can summon
wards. Creature templates are preloaded at boot; summoning does not query Mangos.

The spell supplies health, duration, and the creating spell. Totems inherit their
owner's faction, level, and PvP state. A behavior-tree lifetime check uses explicit
time and owner observations, removing expired, abandoned, distant, or wrong-world
wards even during combat. Player death dismisses wards; creature wards can survive
their caster's death while that owner remains present, matching VMangos.

Area-aura emitters retain their spell but apply no modifier to the totem itself.
Recipients receive the normal modifier. Totem departure removes source-specific
area auras and clears owner tracking. Player world transfer also dismisses totems
through the existing typed-effect path.

Battleground-only spells require actual match membership. Alterac Valley standards
and recall spells additionally require an active or ended Alterac match. The
standard failure code displays the native battleground-only error.

The first native run found a 1,720-HP standard: template stamina was added to the
spell's 1,500 health because its canonical stamina input was absent. The loader now
builds the creature stat inputs before applying spell health. A loader regression
uses a cached fixture with 22 stamina and verifies repeated recomputation remains
at 1,500 HP.

## Native results

Debugmage (GUID 5), Debugpriest (GUID 4), and Debugshaman (GUID 8) entered Arathi
Basin through `.bg join arathi` and the native Enter Battle dialog. All were in
`WorldRef{map_id: 529, instance_id: 1}`. Mage and priest formed a party. Inside
the match, developer teleports placed them near Stables at approximately
`1200 1200 -56`; no map argument was supplied. Developer commands supplied the
items and required honor rank, followed by actual inventory right-clicks.

| Check | Observed result |
| --- | --- |
| Outside battleground | In the first run, right-clicking item 18607 on Programmer Isle displayed “Can only use in battlegrounds” and created no ward. |
| Alliance item use | Item 18606 created the visible Alliance Battle Standard, entry 14465, with exactly 1,500 current and maximum health. The native item tooltip showed its ten-minute cooldown. |
| Party and enemy projection | Spell 23033 raised mage maximum health from 1,875 to 2,156 and priest maximum health from 1,582 to 1,819. The enemy shaman remained at 2,415. Both allies displayed the buff. |
| Enemy destruction | The shaman targeted the standard through the client and cast Lightning Bolt and Chain Lightning. Observed health fell through 1,103, 709, and 337 before death. The model disappeared, tracking cleared, and both allies returned to their baseline maximum health. |
| Range loss and return | A second standard, placed by the priest, retained 1,500 HP. Moving the mage to `1135 1200` removed its bonus while the priest retained hers. Returning restored the mage to 2,156 maximum health. |
| Natural expiry | A read-only sampler observed the priest's standard absent 68 ms after its 120-second deadline. Both allies had baseline maximum health, no source aura, and empty totem tracking. The client model and buff disappeared. |
| Elemental coexistence | The shaman's Horde standard, entry 14466, had 1,500 HP while a 5-HP Strength of Earth Totem occupied slot 2. Both models and both buffs were visible. Horde maximum health rose from 2,415 to 2,777. |
| World departure | `.bg leave` returned the shaman to Programmer Isle. Both summons were offline, tracking was empty, and maximum health returned to 2,415. |
| Other ward and owner death | After learning spell 8832 for this check, the shaman cast Ward of Zanzil through the client. Entry 6386 had 5 HP and an independent key. `.die` invoked player death, removing the ward and clearing tracking. |

The Ward of Zanzil check used a player caster; an NPC casting that spell was not
tested natively. Creature-owner death semantics, multiple independent summons,
other-copy rejection, logout, and Alterac admission are automated coverage. No
Alterac match was claimed. The first run's outside-battleground rejection predates
the stamina fix; the final run rechecked summon health, combat, range, expiry,
coexistence, world departure, and player death.

## Evidence and validation

- Final priest session: `/home/pikdum/.cache/thistle-wow-playtest.ZXKpwh`.
- Final mage session: `/home/pikdum/.cache/thistle-wow-playtest.yVHlsm`.
- Final shaman session: `/home/pikdum/.cache/thistle-wow-playtest.x2Ady4`.
- Mage captures: `standard-1500`, `standard-destroyed`, `expired-clean`.
- Priest captures: `party-buff`, `expired-clean`.
- Shaman captures: `enemy-damage`, `independent-standard`, `departed-clean`,
  `zanzil-ward`, `death-clean`.
- Initial rejection capture:
  `/home/pikdum/.cache/thistle-wow-playtest.GPtXtQ/screenshots/rejected-item.png`.
- Logs: `/tmp/thistle-standards-server.log`,
  `/tmp/thistle-standards-server-final.log`, `/tmp/thistle-standard-expiry.txt`.
- WoW's own gfx counters on RX 7900 XT PCI `0000:0c:00.0` increased from
  14497731096 to 15800572106 ns for priest PID 2335224, 12626765748 to
  13848787364 ns for mage PID 2336230, and 12934362764 to 14339738591 ns for
  shaman PID 2337078.

Final-run logs contain expected duplicate-character login rejections during client
selection and existing unsupported account-data, raid-info, ticket, and meeting
stone requests. No summon, aura, combat, owner, movement, or visibility errors
occurred. All helper-owned clients and retained servers were stopped. Before the
final server shutdown, all three players and all five observed summons were
offline.

Validation on the final source: `mix test.all` passes 5,237 tests;
`mix compile --warnings-as-errors`, `mix credo --strict`, formatting, and
`git diff --check` pass. DBC spell tests remain tagged `:dbc_db`; the new loader
test uses cached fixtures and is tagged `:namigator_maps` because placement calls
the map boundary. No architecture allowlist entries were added.
