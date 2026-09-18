# Beast Lore

Beast Lore (1462) now activates the special-information projection for the
caster. Unit updates include melee/off-hand damage and all seven resistances
for that viewer, while unrelated private fields remain hidden. Bystanders
receive ordinary public fields and no special-information tooltip flag.
Existing self updates retain full field visibility.

Access is derived from current empathy aura holders. The normal aura transition
updates the unit's dynamic flag, and packet encoding personalizes the flag and
field mask for each recipient. Refresh, replacement, removal, expiry, and death
therefore need no separate access cache. Sparse updates without dynamic flags
do not overwrite the client's flag.

References: `Aura::HandleAuraEmpathy` in
`refs/vmangos/src/game/Spells/SpellAuras.cpp`,
`Player::CanSeeSpecialInfoOf` in `refs/vmangos/src/game/Objects/Player.cpp`, and
the special-information visibility and update-field declarations in
`refs/vmangos/src/game/Objects/`.

## Automated acceptance

- Real DBC Beast Lore loads empathy, lasts 30 seconds, and targets beasts.
- Refresh extends access; replacing the caster revokes the former caster's
  access. Removing one of two distinct empathy sources preserves the other.
- Expiry and lethal damage clear access and pending aura events.
- Decoded values/create packets contain the caster's damage and resistance
  fields, including zero resistances, without exposing stats, attack power,
  mana costs, inventory, or money. Bystanders receive public fields only.
- Other dynamic flags survive projection; sparse updates preserve omission.

`mix test.all`: 3,175 passed. `mix compile --warnings-as-errors`: passed.
`mix credo --strict`: zero issues. Logs are
`/tmp/thistle-empathy-{tests,compile,credo}.log`.

## Real-client acceptance

An isolated build-5875 client controlled level-50 Debughunter (GUID 7) on
Programmer Isle. The existing seed supplied Beast Lore and a Stonetusk Boar
(GUID 17379390963919559872). All casts came from the client; runtime probes
only read owner state.

- Before casting, the boar's tooltip showed its name and level/type.
- Beast Lore enabled the expanded tooltip: **5–7 Damage, 103 Armor, 102 Health**,
  diet, and tameability. Server damage was `{5.231049, 6.794351}`, armor was 103,
  and health was 102. The boar remained out of combat.
- The sampler observed application at 1.05 seconds and expiry at 30.96 seconds.
  Flags changed `0 -> 16 -> 0`, and the original caster lost access. A refreshed
  tooltip returned to its ordinary name and level/type display.
- A second cast followed by Arcane Shot killed the boar while Beast Lore was
  still active. At 26.17 seconds in that sample, health reached zero, the holder
  disappeared, and flags became 5 (tap/loot flags, without special information).
  A separate read confirmed `Aura.next_event_at/1` was nil. Hovering the corpse
  showed the ordinary corpse tooltip without damage, armor, or health details.
- After its normal three-minute respawn, the boar had 102 health, flags 0,
  no holders, no pending aura event, and no caster access. Its tooltip again
  showed only the ordinary living-beast information.

The client rebuilds this tooltip on hover. An initial capture retained the old
tooltip text until it was refreshed. Both `GameTooltip:SetUnit("target")` and
ordinary mouse re-entry displayed the correct active information; ordinary
hover also confirmed expiry and death cleanup.

Bystander packet isolation, refresh/replacement, and overlapping sources were
verified by automated tests rather than a second client session. No owner or
cast-validation errors occurred. Login produced the existing unsupported
account-data, raid-info, GM-ticket, time-query, and meeting-stone warnings.

Evidence:

- `/tmp/thistle-empathy-server.log`
- `/tmp/thistle-empathy-active.txt`
- `/tmp/thistle-empathy-lifecycle.txt`
- `/tmp/thistle-empathy-death.txt`
- `/tmp/thistle-empathy-dead-state.txt`
- `/tmp/thistle-empathy-respawn.txt`
- `/home/pikdum/.cache/thistle-wow-playtest.kyO5zi/screenshots/`, particularly
  `clicked-boar.png`, `lore-hover.png`, `after-expiry.png`, `corpse-tooltip.png`,
  and `respawn-tooltip.png`.

The helper-owned client and server were stopped; logs and screenshots were
retained.
