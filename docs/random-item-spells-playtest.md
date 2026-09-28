# Random item spell acceptance

Implementation: `9a03eefd`, checked against VMangos reference
`8f4e608450460efe1e38743e4da74397d4773a3a`.

## Behavior and references

Goblin Jumper Cables (7148, spell 8342) succeed 33% of the time; the XL
version (18587, spell 22999) succeeds 50% of the time. Failure casts 8338
or 23055 on the engineer, respectively, dealing 50 or 100 damage and
stunning for two seconds. Success offers 15% of the recipient's maximum
health and mana. The reference is `src/scripts/spells/spell_item.cpp`,
`GoblinJumperCablesScript` and `GoblinJumperCablesXLScript`.

Six Demon Bag (7734, spell 14537) follows `SpellEffects.cpp`, case 14537:

| Outcome | Chance | Recipient |
| --- | ---: | --- |
| Fireball, 11921 | 25% | Target |
| Frostbolt, 13322 | 25% | Target |
| Chain Lightning, 21179 | 20% | Target and chain recipients |
| Polymorph, 13323 | 7% | Target |
| Polymorph backfire, 13323 | 3% | Caster |
| Enveloping Winds, 25189 | 15% | Target |
| Summon Felhound Minion, 14642 | 5% | Caster |

The felhound uses creature entry 9556 and the spell data's 30-second
guardian lifetime. All child spells retain the item's GUID. Shared spell
resolution supplies resist outcomes, chaining, aura control and expiry,
and guardian ownership and cleanup.

The pure item logic emits weighted typed effects. Successful cable rolls
select an `OfferResurrection` command; the recipient's event sink then
calls the existing offer transition. A failed roll never records an offer
or sends a resurrection prompt. The transition still rejects duplicate
offers and recipients who have already revived. Ordinary resurrection
spells retain their immediate offer behavior. Self-polymorph explicitly
retains the target role needed to apply hostile effects to the caster.

## Native setup and cable acceptance

Debugmage (5) and Debugpaladin (2), level 60 and Engineering 300, used two
isolated GPU-rendered build-5875 clients on Programmer Isle. Existing
learning, item, profession, death, health and teleport commands prepared
the scenario. Learned parent spells sampled random outcomes before actual
equipped item uses. Random values and live entity state were not altered;
Tidewave inspected the owners and sampled cast completion.

| Action | Client and authoritative result |
| --- | --- |
| Mage casts learned normal Defibrillate on dead paladin | Failure left no offer; the completion sample recorded mage health 2300/2350 and aura 8338. |
| A later normal cast succeeds | The paladin saw the resurrection dialog; the offer contained caster 5, health 490 and mana 400. |
| Paladin accepts | First live sample was exactly 490 health, 400 mana, no pending offer, and the mage's position `{16320, 16305, 69.44445}`. |
| Paladin casts learned XL Defibrillate on dead mage | The mage received an offer for 352 health and 630 mana, from caster 2. Declining cleared it. |
| Paladin uses equipped XL cables | Failure reduced health from 3271 to 3171, applied aura 23055, and left the mage without an offer. |
| Mage uses equipped normal cables | Failure applied aura 8338 and left the paladin without an offer. |
| Immediately reuse either equipped cable item | Each client displayed "Item is not ready yet." Each retained cooldown identified its actual item and category 1051, with a deadline exactly 1,800,000 ms after its start. |
| Recover after the failed item attempts | Ordinary Redemption still offered resurrection and both clients accepted it successfully. |

## Bag acceptance

The players accepted native duels. God mode prevented health loss during
repeated bag casts; the cable damage checks above ran without god mode.

- The mage equipped and used the actual bag. Its child Fireball was
  resisted by the paladin, and the mage's client reported that result.
  The cooldown retained item 7734, category 1141, a 1,800,000-ms item
  deadline, and a 10,000-ms category deadline.
- Native parent casts produced visible frost, fire, wind, and lightning
  effects. A lightning screenshot shows multiple recipients; frost and
  wind holders on the mage retained caster 2 and expired normally.
- A native parent cast summoned felhound 9556 with owner 2. Both clients
  displayed it. The sampled creature was level 54 with 2533 health.
- After that guardian's deadline, its process, metadata, and spatial
  position were absent and the paladin's guardian map was empty. The
  recorded guardian GUID was `17383894721977385212`.
- A later parent cast selected the self-polymorph backfire. The paladin's
  owner recorded holder 13323, caster 2, and sheep display 856. Both clients
  showed the sheep and the caster's client rejected another cast while
  polymorphed. After natural removal, display 50 returned and one second
  of native forward movement moved the paladin about 7.1 yards.

The rare backfire was inspected with temporary outcome logging that did
not change selection or delivery. Live recompilation of the resolver
caused transient unavailable-module errors in background mob ticks. The
logging was removed, and item acceptance was repeated on a fresh server
with the final code loaded at startup. The earlier log retains those
diagnostic reload errors.

The fresh run repeated both equipped cable uses: normal cables failed
without an offer, and XL cables succeeded. The mage accepted the XL offer
and the first live sample recorded exactly 369 health and 657 mana, with
the pending offer cleared. These amounts reflect the new seed's equipment
and 15% of its resulting maxima.

The mage again used the actual bag and retained its item cooldown. Native
parent casts again produced self-polymorph and a guardian, this time with
GUID `17383894721977385142`. Both clients showed the sheep and felhound.
Natural cleanup restored display 50, removed the guardian process and
projections, and emptied the owner's guardian map. One second of native
forward input moved the paladin from `{16504.8700, 16317.4567, 69.4584}` to
`{16511.7305, 16319.3184, 69.5564}`. The final server log has no errors; its
only warnings are the existing account-data and GM-ticket stubs.

## Automated checks and artifacts

- `mix test.all`: **7,405 passed**, 69.4 seconds on the final run.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues; the commit hook also passed.
- Deterministic tests exhaust all weighted outcomes and both cable
  success percentages. Real-data tests cover child damage and stun expiry,
  no offer after failure, success projection, duplicate/stale offer
  rejection, chain recipients, target and self-polymorph, and the guardian
  request's ownership and lifetime. The architecture ratchet passes without
  new allowlist entries.

Evidence remains in:

- Mage client: `/home/pikdum/.cache/thistle-wow-playtest.zTAZjH`.
- Paladin client: `/home/pikdum/.cache/thistle-wow-playtest.1tVTdT`.
- WoW processes 2720898 and 2721632 both reported `amdgpu`, nonzero graphics
  engine counters, and allocated VRAM through their own DRM file descriptors.
- Cable snapshots: `/tmp/thistle-item-cables-*.log`.
- Bag snapshots: `/tmp/thistle-item-bag-*.log`.
- Initial server log: `/tmp/thistle-item-outcomes-server.log`.
- Final server log: `/tmp/thistle-item-outcomes-final-server.log`.
- Final snapshots: `/tmp/thistle-item-final-*.log`.
- Final test, compiler and lint logs:
  `/tmp/thistle-item-outcomes-final-{tests,compile,credo}.log`.

Both helper-owned client services and both retained servers were stopped
after acceptance. Logs and screenshots were retained.
