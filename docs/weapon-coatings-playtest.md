# Charged weapon coatings

Temporary weapon enchants now load their finite charge counts from VMangos
`spell_enchant_charges` at startup. Instant Poison starts with 40 charges,
Deadly Poison with 60, and Mind-numbing Poison with 50. A missing charge row
means unlimited procs, preserving ordinary Shaman imbues.

Successful weapon-enchantment proc rolls consume a charge on the striking
weapon. Missed attacks and failed proc rolls consume nothing. The final
charge still triggers its spell, then removes the temporary enchant, its
visible weapon effect, timer, and equipment bonuses. Permanent enchants
remain independent. The existing spell engine resolves poison damage,
periodic effects, resistance, and debuffs after the proc decision.

Proc resolution applies spell-family chance modifiers, including Improved
Poisons. Unequipped, broken, disarmed main-hand, and feral weapons retain
their existing restrictions. Dead or ghost wielders cannot trigger new
weapon procs from delayed combat feedback. Enchant tokens prevent stale
expiration messages from clearing a replacement, and each proc checks that
its source is still active before executing.

Application validates the owned target and commits the enchant, reagents,
and consumable together through `Inventory.Batch` and `ChangeSet`. Item use
leaves consumption to that transaction for both instant and timed casts.
Temporary coatings use their target's equipment requirements, without the
minimum item-level restriction used by permanent enchants. Reapplication
replaces the coating and renews its duration and charges. Login restores
remaining charges and the existing expiration deadline.

The client binding prompt exposed a related mail omission. Mail now rejects
items bound by active enchantments as well as ordinary soulbound items.
Temporary binding ends with the coating; it does not permanently set the
item's soulbound flag. Rejection preserves the item and postage.

References: `Spell::EffectEnchantItemTmp`, `Player::CastItemCombatSpell`,
`Item::IsBoundByEnchant`, and item-target validation in
`refs/vmangos/src/game/Spells/Spell.cpp`. The separate
`CMSG_CANCEL_TEMP_ENCHANTMENT` packet is a later-client feature and is not
added to the Vanilla protocol.

## Automated coverage

- VMangos charge counts and the build-5875 Improved Poisons family mask,
  with DBC and VMangos tests kept separate.
- Packed item charge fields, unlimited enchants, final-charge removal,
  permanent-slot preservation, and stale tokens.
- Atomic application and cost failure, interrupted casts, instant item use,
  and owner-context delivery.
- Failed rolls and avoided attacks, final proc delivery, hand selection,
  bagged and broken weapons, and multiple effects sharing the last charge.
- Death, reconnect restoration, expired login cleanup, and derived bonuses.
- Synthetic and real-DBC poison chance modifiers, plus enchant-bound mail
  rejection and temporary binding cleanup.

## Real-client acceptance

An isolated World of Warcraft 1.12.1 build-5875 client controlled Debugrogue
against a fresh local server. Item use, equipment changes, combat, and
logout actions came from the client. Runtime probes read the owning player,
item store, and targeted creature.

The character equipped an ordinary level-one Worn Dagger, acquired five
Instant Poison vials, and learned Improved Poisons rank five. Interrupting
an application after accepting the binding prompt left all five vials and
no coating. Completing the next application consumed exactly one vial and
created enchant 323 with 40 charges and a 30-minute timer. The client's
`GetWeaponEnchantInfo()` also reported 40 charges.

With only the coated dagger equipped, normal attacks against the seeded
Ironhide Devilsaur consumed charges. The first authoritative combat sample
showed 34 charges and target health 7,728/8,097. A later sample showed 24
charges and 7,282 health, with the original expiration deadline unchanged.
The client combat log displayed Instant Poison's Nature damage and partial
resists. Combat continued through natural exhaustion: the enchant icon
disappeared and the authoritative temporary slot became empty while all
four unused vials remained. Target health was 5,776/8,097 at the follow-up
sample.

Applying another vial restored 40 charges. Replacing that active coating
consumed one further vial, kept a single 40-charge enchant, and renewed its
expiration deadline. Two unused vials remained.

After another three procs, `.die` reduced the wielder's health to zero while
retaining 37 charges and the replacement's exact expiration deadline.
Logout removed the player owner. Login created a different owner and
restored the character as a ghost with the same 37 charges, two unused
vials, and unchanged deadline. The client also reported 37 charges.

The real-client run covered Instant Poison application, interruption,
combat damage, exhaustion, replacement, death, and reconnect. Other poison
charge counts, unlimited imbues, expiry, permanent-slot preservation, and
mail rejection were covered by automated tests. No second observer client
was used, and the 30-minute timer was not waited out in the client.

A temporary client diagnostic called the unavailable Vanilla `StopAttack`
Lua function when depletion occurred; that diagnostic was removed. The
depletion result was verified separately from the disappearing icon and
authoritative item state. No error-level server logs occurred. Existing
unsupported account-data, raid-info, GM-ticket, time-query, meeting-stone,
and cancel-trade requests appeared during ordinary startup/logout. The
helper-owned client and retained server were stopped after acceptance.

Client artifacts:
`/home/pikdum/.cache/thistle-wow-playtest.v4vidy/screenshots/`.
Runtime evidence: `/tmp/thistle-poison-*.txt`.
Server log: `/tmp/thistle-poison-server.log`.

## Validation

- `mix test.all`: 3,512 tests passed after the final code changes.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: no issues.
- Full-suite log: `/tmp/thistle-poison-final-tests.log`.
