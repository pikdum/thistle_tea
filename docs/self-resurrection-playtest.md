# Self-resurrection

Soulstone protection is captured at the lethal health transition before death
removes temporary auras. All five Vanilla ranks supply their corresponding
Use Soulstone spell to the death dialog. Protection is consumed on death;
resurrection consumes the offer, and releasing spirit forfeits it. A Soulstone
also retains its offer across Spirit of Redemption's final death.

Reincarnation uses the same boundary. It is offered only when the passive is
known, an Ankh is carried, and the spell/category cooldown is ready. Using it
plans the reagent transaction before committing any changes. A successful use
consumes one Ankh, restores health and mana, and starts the shared one-hour
cooldown. Improved Reincarnation modifies both the cooldown and restoration.
Soulstones take priority over Reincarnation without consuming its reagent or
starting its cooldown.

Restoration uses the self-resurrection effect from the spell data: negative
amounts specify flat health with mana in the miscellaneous field; positive
amounts specify a percentage of maximum health and mana. Rage is cleared and
energy restored to maximum. Resource restoration is capped, including a zero
mana pool. The client message only dispatches; pure gameplay logic owns the
offer and restoration, while the player boundary loads spell data, commits
inventory changes, and updates visibility.

Reference behavior: `refs/vmangos/src/game/Objects/Player.cpp`,
`SelectResurrectionSpellId`; `refs/vmangos/src/game/Spells/SpellEffects.cpp`,
`EffectSelfResurrect`. The Vanilla client uses `PLAYER_SELF_RES_SPELL` and
`CMSG_SELF_RES`. This work covers Soulstones and Reincarnation; the Twisting
Nether trinket proc is not implemented here.

## Validation

Default tests cover all Soulstone ranks, expiry, consumption, spirit release,
Spirit of Redemption offer retention, resource limits, invalid/repeated
requests, Reincarnation prerequisites, shared cooldowns, and talent modifiers.
DBC-tagged tests check actual restoration amounts, reagents, categories, and
talent data without querying the VMangos database.

Client acceptance uses the isolated build-5875 session at
`/home/pikdum/.cache/thistle-wow-playtest.kCqhUN`. The initial server log is
`/tmp/thistle-self-res-server.log`; the final build uses
`/tmp/thistle-self-res-server-final.log`.

- Debugwarrior consumed a Minor Soulstone through `UseContainerItem`, applying
  aura 20707. After `.die`, the client showed Use Soulstone and owner state
  showed health zero, offer 3026, and no remaining Soulstone aura.
- Clicking Use Soulstone restored life and cleared the offer. Movement worked.
  A second death showed no Soulstone option.
- This exposed a pre-existing restoration clamp bug: a warrior could receive
  mana despite having no mana pool. The shared resurrection clamp now respects
  a maximum of zero, with regression coverage.
- On the final build, Debugshaman began with 2,415 maximum health, 2,430 maximum
  mana, 20 Ankhs, and no cooldown. The client offered Reincarnation on death.
  A read-only sampler captured the first live state after clicking it: 483
  health, 486 mana, 19 Ankhs, a cleared offer, no root, and 3,599,964 ms of
  cooldown remaining. These are exactly the expected 20% resource values.
- A second death during that cooldown showed only Release Spirit. The owner
  retained the category cooldown and had self-resurrection spell zero.
- After corpse recovery, the same shaman consumed a Minor Soulstone and died
  while Reincarnation was still cooling down. Use Soulstone appeared and
  restored exactly 400 health and 700 mana. The Ankh count stayed at 19 and
  both existing category cooldown timestamps were unchanged. The offer was
  cleared, the owner was alive and unrooted, and client movement succeeded.

Read-only samples are retained in `/tmp/thistle-self-res-shaman-before.txt`,
`/tmp/thistle-self-res-shaman-after.txt`,
`/tmp/thistle-self-res-shaman-second-death.txt`,
`/tmp/thistle-self-res-soulstone-before.txt`,
`/tmp/thistle-self-res-soulstone-after.txt`, and
`/tmp/thistle-self-res-final-movement.txt`. Screenshots include
`soulstone-death.png`, `soulstone-spent.png`, `reincarnation-offer.png`,
`reincarnation-cooldown.png`, `soulstone-during-cooldown.png`, and
`soulstone-final-resurrected.png` under the session's `screenshots/` directory.

Final automated gates: `mix compile --warnings-as-errors`, `mix test.all`
(2,913 passing), `mix credo --strict`, formatting, and `git diff --check`.

The final server log contains no gameplay or entity-owner errors. Existing
unsupported housekeeping requests (account data, raid info, tickets, time,
meeting stones, and trade cancellation) are still logged; this acceptance
does not establish full protocol coverage.
