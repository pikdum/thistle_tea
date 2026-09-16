# Exclusive resistance effects

Exclusive resistance auras now contribute the strongest positive and strongest
negative amount independently for each school. Ordinary resistance modifiers
remain additive. Selection uses active holders, including their stack counts,
so application order does not matter and removing an effect restores the next
strongest contribution without deleting other buffs. The existing stat
recompute and aura transition own the resulting fields and client updates.

Reference: `Aura::HandleAuraModResistanceExclusive` in
`refs/vmangos/src/game/Spells/SpellAuras.cpp`.

Real-spell testing also found that DBC effect selectors were loaded unsigned.
Mark of the Wild's all-stat selector therefore arrived as 4294967295 instead
of -1, silently disabling its stat bonus. The spell loader now uses its existing
signed-32-bit conversion for effect miscellaneous values, matching
`SpellEntry::EffectMiscValue` in VMangos. Item and display-ID special cases
retain their existing handling.

## Validation

- `mix test.all`: 2,942 passed.
- `mix compile --warnings-as-errors` and `mix credo --strict`: passed.
- Pure tests cover school overlap, positive/negative selection, ordinary
  additive effects, equipment and base inputs, stack counts, multipliers,
  duplicate strengths, removal fallback, application order, and idempotence.
- A `:dbc_db` regression applies actual Mark of the Wild (9885) and Fire
  Resistance Aura (19891) in both orders, cancels the stronger aura, and
  expires Mark. It checks resistance, armor, intellect, retained holders,
  and the broadcast flag.

## Real-client acceptance

Used level-60 Debugshaman on Programmer Isle with an isolated build-5875
client. Existing `.learn` commands supplied the spells. Casts used the client
spell API; cancellation used right-clicks on buff icons. Client `UnitResistance`
and `UnitStat` reads were printed in chat, separately checked against read-only
Tidewave owner probes for GUID 8.

- Baseline fire resistance was 0 and intellect 113.
- Mark alone gave fire/frost resistance 20 and intellect 125.
- Adding Fire Resistance Aura gave fire 30 and frost 20, retaining both buffs.
- Cancelling fire protection immediately restored fire 20 with Mark intact.
- Cancelling Mark returned fire to 0 and intellect to 113.
- Reversing cast order again gave fire 30 and frost 20 with both buffs intact.
- Removing the weaker Mark left fire 30, restored frost 0, and intellect 113.

Natural expiry was covered by the automated DBC lifecycle test; the client
session used cancellation. These resistance fields are private player fields,
so no second graphical observer was needed. No gameplay or owner errors
appeared. Existing unimplemented account-data, raid-info, GM-ticket, query-time,
and meeting-stone requests were unrelated to this feature.

Evidence: `/home/pikdum/.cache/thistle-wow-playtest.V4LkV3/screenshots/`,
`/tmp/thistle-resistance-server-final.log`,
`/tmp/thistle-resistance-{mark,both,fallback,reverse}-state.txt`, and
`/tmp/thistle-resistance-{all,compile,credo-final}.log`.
