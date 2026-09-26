# Death-item reward acceptance

Validated with the build-5875 client on 2026-09-25 (America/Chicago).
Reference: `refs/vmangos` at `8f4e60845`, specifically
`Aura::HandleChannelDeathItem`, `Player::IsHonorOrXPTarget`,
`Creature::IsTappedBy`, and `SpellAuraHolder::GetCaster`.

## Implementation

- `eb1af243`: capture reward requests at the lethal health transition before
  aura cleanup; resolve the caster's current level and original group tap at
  the boundary. Soul Shards accept eligible player victims and grouped creature
  kills. Non-shard capture rewards do not inherit shard-only level/tap rules.
  Warlock rewards are deduplicated per caster; generic rewards remain separate.
  Missing item IDs and nonpositive quantities produce no reward.
- `4d78513a`: death rewards report inventory errors and grant only the quantity
  that fits, using one inventory plan and commit. Capacity includes compatible
  bags, partial stacks, and banked unique-item limits. Ordinary spell creation
  retains its existing behavior.
- `5191f272`: starting quantities now split into legal stacks through the same
  inventory plan. A grant that cannot fit commits nothing. The debug warlock
  starts with five separate shards, replacing the invalid stack of 100 exposed
  during acceptance setup.

The existing Shadowburn effect order was correct: its reward aura precedes
its damage. No spell-effect reordering was introduced. Pure reward logic has
no world, party, registry, or database dependency. The architecture dependency
allowlist is unchanged.

## Native acceptance

Final acceptance used a fresh server at `5191f272`. Debugwarlock and
Debugbidder used separate accounts/clients on Programmer Isle; Debugrival
provided the opposing-faction player victim. Inputs were ordinary client
casts, party actions, item grants, and existing developer setup commands.
Tidewave sampled owner state read-only. Each isolated client used hardware
OpenGL; the WoW process's own `amdgpu` DRM counters increased.

| Scenario | Client evidence | Owner-state evidence |
| --- | --- | --- |
| Grouped Drain Soul | Drain channel followed by “You create: [Soul Shard]” | Level-20 warlock went from five to six shards while the level-18 creature retained Debugbidder's tap and group ID 1. Death cleared its auras and the caster's channel. The shard count stayed six after respawn. |
| Gray-target capture | Capture Felhound Spirit produced an Imprisoned Felhound Spirit | Level-50 caster received exactly one item 12648 from the level-18 victim. Samples captured the active reward aura, lethal periodic tick, inventory arrival, and channel cleanup. |
| Full inventory | Capture Infernal Spirit displayed “Inventory is full” | With no free compatible slots, the victim died under spell 16628 and item 12649 remained absent. Existing inventory remained intact. A client UI-error listener also copied the normal error into chat for a retained screenshot. |
| Lethal PvP Shadowburn | Warlock displayed the kill and a new Soul Shard; rival displayed the death dialog | Rank 5 (18870) killed level-50 Debugrival. Eight shard GUIDs became seven when the reagent was consumed, then eight with a new GUID when the reward arrived. Temporary auras were removed. |
| Victim releases spirit | Rival entered ghost form | Victim health became 1 and player flags included 16; the warlock still had eight shards and no extra reward. |
| Logout and reconnect | Character list showed a completed logout; backpack contents reappeared after login in Stormwind | The owner process was absent while logged out. Before/after snapshots matched every item GUID, entry, and stack count, including eight shards and one Felhound Spirit. |

All reward casts above used the normal spell and inventory paths. The initial
capture attempts that expired before the killing blow produced no item.

## Automated validation

`mix test.all`: **6,283 passed**. `mix compile --warnings-as-errors`,
`mix credo --strict`, formatting, and commit hooks passed.

Regressions cover current caster levels, original group taps, later group
changes, battleground membership, missing/non-player casters, player victims,
pets/totems/zero-experience creatures, gray capture targets, per-caster warlock
deduplication, independent generic rewards, invalid quantities, and the single
lethal transition. DBC tests exercise every Shadowburn rank, resisted/expired
Shadowburn, all Drain Soul ranks, capture spells, and Infernal Fire's zero count.
Inventory tests verify partial delivery, packet notifications, unique limits,
full-bag rollback, soul-bag compatibility, legal starting stacks, and absence
of orphaned items.

## Retained evidence

- Warlock session: `/home/pikdum/.cache/thistle-wow-playtest.xKqnz8`.
  Screenshots: `fresh-group-drain.png`, `grouped-shard-reward.png`,
  `gray-capture-complete.png`, `full-inventory-feedback.png`,
  `pvp-shadowburn-kill.png`, `logged-out.png`, `reconnected-inventory.png`.
- Mage session: `/home/pikdum/.cache/thistle-wow-playtest.jg22VP`.
- Rival session: `/home/pikdum/.cache/thistle-wow-playtest.gpA4H6`.
  Screenshots: `pvp-shadowburn-victim.png`, `released.png`.
- Group samples: `/tmp/thistle-death-group-fresh.log`,
  `/tmp/thistle-death-group-result.log`.
- Capture samples: `/tmp/thistle-death-capture-success.log`,
  `/tmp/thistle-death-full-success.log`.
- PvP/release samples: `/tmp/thistle-death-pvp-sample.log`,
  `/tmp/thistle-death-release.log`.
- Reconnect snapshots: `/tmp/thistle-death-before-reconnect.log`,
  `/tmp/thistle-death-after-reconnect.log` (identical).
- Server: `/tmp/thistle-death-item-fresh-server.log`.
- GPU evidence: `/tmp/thistle-death-item-gpu-{warlock,mage,rival}.log`.
- Checks: `/tmp/thistle-death-item-final-{tests,compile,credo}.log`.

The acceptance server log contains no owner crashes or unsupported aura/effect
errors. Existing login warnings for account-data, GM-ticket, and meeting-stone
messages remain outside this reward path.

All three helper-owned client sessions were stopped through their recorded
systemd units. The acceptance server and superseded setup servers were stopped;
logs and screenshots remain available locally. No push or deployment was performed.
