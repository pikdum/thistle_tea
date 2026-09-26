# Trap activation and Entrapment

Hunter trap hits now carry the trap-activation proc flag. Non-damaging trap
applications report their successful hit to the caster through a typed effect;
Explosive Trap combines activation with its existing damage feedback, avoiding
a second roll for the same hit. Frost Trap reports a trap-activation event on
each two-second periodic trigger. Its 250-ms area refreshes do not roll procs.

The caster's current aura holders own eligibility, chance, charges, and cooldowns.
Entrapment uses the ordinary triggered-spell and root lifecycle, including
caster attribution, immunity, diminishing returns, expiry, and talent removal.
No gameplay database queries, additional timers, or architecture allowlist
entries were added.

## Reference and data

Reference revision: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`.

- `Spell.cpp`, trap proc flag construction: hunter family mask `0x1C` adds
  `PROC_FLAG_ON_TRAP_ACTIVATION` (`0x00200000`) to successful direct hits.
- `spell_hunter.cpp`, `HunterFrostTrapAuraScript`: periodic triggers on spell
  13810 ask the caster to check trap-activation procs against that recipient.
- `spell_proc_event`, entry 19184: hunter family mask `0x14` permits fire and
  frost trap effects, excluding Freezing Trap. Talent ranks inherit this rule.
- DBC Entrapment ranks 19184, 19387, 19388, 19389, and 19390 have chances of
  5%, 10%, 15%, 20%, and 25%, respectively. They trigger root spell 19185.
- Rank five also retains its DBC damage/periodic proc flags. The new activation
  flag is combined with direct damage in one eligibility check.

## Bugs found during acceptance

The first native Frost Trap made its ground visual but repeatedly failed its
area ticks: the synthetic trap caster used a partial unit map lacking `spirit`,
which spell snapshot construction requires. Trap casters now use the complete
`Unit` component. A spawned-object regression activates an owned Frost Trap
and receives both ground effects from its real dynamic-object processes.

Reviewing this activation path also exposed overly broad target selection.
Owned traps accepted idle neutral creatures and could flag an unflagged hunter
through a flagged enemy. Selection now uses the shared hostility and PvP rules,
requiring a hostile target or an attackable target already in combat. Tests
cover neutral activation after combat begins, hostile creatures, dead targets,
and owner PvP flags. Environmental trap selection is preserved.

## Native acceptance

Two isolated GPU-rendered build-5875 clients used level-50 Debughunter and
Debugbidder. All setup, talent learning/reset, trap casts, duel actions, and
movement came through the clients; Tidewave probes were read-only. Final
gameplay source was `69fa275f`, without source changes during the runs.

The first corrected-server trace recorded repeated roots from hunter GUID 7:

- Frost Trap's recipient holder advanced its trigger deadline by two seconds.
- Entrapment appeared at the 7,932-ms sample and lasted 5,000 ms.
- Further procs lasted 2,500 and 1,250 ms under ordinary diminishing returns.
- Root flags cleared after each expiry; Frost Trap's holder disappeared at
  the ground effect's deadline.

A movement follow-up was discarded after a character died outside the test
area. A fresh server repeated acceptance at `{16300, 16350, 69.44}` on map 451,
with god mode protecting health and the pet in passive follow. Entrapment's
native chance remained 25%; no proc chances or aura state were modified.

In the accepted movement trace, Frost Trap appeared at 4,417 ms and Entrapment
at 6,405 ms. The client displayed both debuffs and root feedback. A movement
attempt during the root left the authoritative position unchanged. The root
expired at 11,423 ms. Subsequent movement traversed the slowed field; at
19,383 ms the area holder disappeared near its ten-yard edge, more than
14 seconds before the field's deadline. Movement continued without new roots.

In a subsequent native duel, `.talents reset` removed rank five from both the
hunter's spellbook and aura holders at the 7,593-ms sample. Frost Trap continued
its two-second checks until its 30-second lifetime ended, without any
Entrapment roots. Logout removed the hunter's process, metadata, spatial entry,
and area registrations. Reconnecting restored the character and pet while
keeping Entrapment unlearned and inactive.

Both accepted server logs were free of gameplay errors and cast-validation
failures. Existing unsupported account-data, ticket, and meeting-stone
requests remained. One restart attempt hit `eaddrinuse` while the old BEAM
was still at its break prompt; it exited unsuccessfully. The old process was
then stopped and its terminal result checked before the accepted fresh run.

All four helper-owned client services and all server processes were stopped.
Final disconnect probes found neither player nor the restored pet in the
entity registry, metadata, or spatial index. Artifacts were retained.

The accepted clients' own GPU counters increased, using one DRM client ID per
WoW process without summing duplicate file descriptors:

| WoW PID | DRM client | Initial graphics time | Final graphics time |
| --- | --- | --- | --- |
| 1730216 | 5263 | 3,251,977,708 ns | 28,374,563,705 ns |
| 1730292 | 5267 | 3,114,547,263 ns | 26,107,200,229 ns |

## Automated coverage

Tests cover every talent rank and its inherited restrictions; successful
non-damaging trap feedback through the event sink and caster proc handler;
one combined Explosive Trap check; resisted applications; exact periodic
cadence; area refreshes; leaving the area; source removal; expiry; death;
talent removal; and actual spawned Frost Trap recipient delivery.

Final validation after the DBC fixture isolation change:

- `mix test.all`: 6,663 passed in 71.6 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: no issues.

Logs: `/tmp/thistle-trap-complete-tests.log` and
`/tmp/thistle-trap-complete-credo.log`.

## Evidence

- Initial crash: `/tmp/thistle-trap-server.log`.
- First corrected server: `/tmp/thistle-trap-final-server.log` and
  `/tmp/thistle-trap-final-trace.txt`.
- Fresh movement/reset server: `/tmp/thistle-trap-repeat-server.log`.
- Movement: `/tmp/thistle-trap-repeat-root.txt` and
  `/tmp/thistle-trap-repeat-movement.txt`.
- Talent and lifecycle: `/tmp/thistle-trap-reset-trace.txt`,
  `/tmp/thistle-trap-logout.txt`, `/tmp/thistle-trap-reconnected.txt`, and
  `/tmp/thistle-trap-cleanup.txt`.
- Screenshots: `/home/pikdum/.cache/thistle-wow-playtest.Yua5kx/screenshots/`,
  including `accepted-root`, `accepted-blocked-movement`, and
  `accepted-outside-field`; hunter screenshots are under session `ig9nQH`.

This change does not establish complete trap or vanilla feature parity.
