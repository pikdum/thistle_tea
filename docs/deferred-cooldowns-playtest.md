# Deferred spell cooldowns

Spells with `cooldown_on_event` remain disabled until their associated aura or
owned game object releases the cooldown. Each cast retains its source spell,
item template ID, item cooldown overrides, category, and start generation.
Activation applies the caster's current cooldown modifiers and creates separate
spell and category deadlines. Repeated completion messages and callbacks from
an older cast cannot restart or cancel the current timer.

Aura removal uses the original caster, including when another entity owns the
aura. Replacing a holder with the same spell and caster keeps the lock pending.
Ordinary owned game objects release the cooldown when removed; rituals release
it on completion. An unfinished ritual clears its pending lock when canceled.
Channel cancellation clears that lock synchronously, before object cleanup,
so saving during logout cannot retain a stranded ritual cooldown.

Login projects stored cooldown sources, including item spells outside the
spellbook. Pending cooldowns use the client's permanent flag, while active
entries carry the remaining spell and category times and original item ID.
Login also restores the client spell-modifier table from retained auras.
Without that restoration, Camouflage still reduced the server's Stealth timer
after reconnect, but the client displayed the unmodified cooldown.

`Spell.Cooldowns` owns the pure transitions and category queries. Aura and
object lifecycles deliver typed `ActivateCooldown` effects to the caster's
entity process. Owner-local effects use `EventSink.Context`; packet projection
uses the existing cooldown codecs. No database queries were added to cooldown
transitions, and the architecture dependency allowlist is unchanged.

Local references: VMangos `Player::AddCooldown`, `Player::SendInitialSpells`,
`SpellAuraHolder` removal, `Unit` owned-object removal, and
`GameObject::FinishRitual`. `Spell::CheckCast` uses `DONT_REPORT` for cooldown
rejection of deferred spells, including global cooldown rejection, to avoid
leaving the client disabled incorrectly. Cancellation of unfinished rituals
clears the local pending lock; this cleanup is an implementation decision,
not a claim that VMangos's cancellation path explicitly clears it.

Automated regressions cover item overrides and reconnect projection, current
modifiers, shared categories, category reset, caster routing, holder replacement,
stale generations, duplicate events, pending cast rejection, client modifier
restoration, synchronous channel cancellation, and actual game-object process
termination. Ritual completion and its later duplicate teardown are exercised
through the game-object server callback and owner packet projection.

## Native acceptance

An isolated build-5875 client used Debugrogue (GUID 3) and Debugwarlock (GUID 6)
on Programmer Isle. All gameplay changes came from native client actions or
existing chat development commands. Tidewave probes only read state.

For the rogue, `.learn 14177` supplied Cold Blood and `.learn 14065` supplied
Camouflage rank 5. Cold Blood was placed on action slot 2 and cast normally.
The pending entry projected `spell_ms: 1`, `category_ms: 2147483648`; the client
reported duration `0.001`, enabled `0`. After normal logout, the character was
offline and retained both its pending cooldown and aura. Reconnect restored
the same disabled client state.

Right-clicking Cold Blood's buff removed it and changed the entry from pending
to active. A 40 ms sampler observed 179,972 ms remaining at its first sample;
the client reported duration `180`, enabled `1`.

Stealth rank 3 (1786) initially exposed the missing modifier restoration after
reconnect: the authoritative timer was five seconds but the client showed ten.
After the login fix, the rogue reconnected with Stealth still active. Removing
the buff produced 4,976 ms remaining at the first sampled transition. A fresh
cast and removal then reported duration `5`, enabled `1` through the native
`GetSpellCooldown` API. Another cast after expiry succeeded and restored both
the aura and pending entry. The owner retained Camouflage's modifier totals
`{:flat, 22, 11} => -5000` and `{:flat, 22, 12} => 15`.

For the warlock, `.learn 18540` and `.additem 16583 5` supplied Ritual of Doom
and Demonic Figurines. Casting and clicking the ground created a visible Doom
Portal, an active channel, and a pending cooldown. Movement canceled all three:
the owner had no cast, channel object, or pending entry, and the old object
process no longer existed. An immediate second cast created a different portal
and generation. Logging out during that channel left no saved cast or pending
entry and stopped its object. After reconnect the client reported duration `0`,
enabled `1`. Full ritual completion is covered by automated lifecycle checks;
the native run exercised cancellation and logout.

The client used its own AMD GPU context. Its DRM graphics counter advanced
from 3,628,014,629 to 35,723,687,789 ns. The exact helper-owned systemd session
and retained server were stopped after acceptance. No server errors occurred;
existing unrelated login/UI warnings remain for account data, raid information,
GM tickets, and meeting-stone information.

Local evidence is retained in:

- `/home/pikdum/.cache/thistle-wow-playtest.TfPgCA/screenshots/`, particularly
  `acceptance-reconnected-cooldown.png`, `acceptance-cold-blood-released.png`,
  `acceptance-stealth-five-seconds.png`, `acceptance-ritual-channel.png`, and
  `acceptance-ritual-reconnect.png`.
- `/tmp/thistle-deferred-native-pending.txt`,
  `/tmp/thistle-deferred-native-offline.txt`,
  `/tmp/thistle-deferred-native-release.txt`,
  `/tmp/thistle-deferred-native-stealth-final.txt`, and
  `/tmp/thistle-deferred-native-final.txt`.
- `/tmp/thistle-deferred-native-ritual-pending.txt`,
  `/tmp/thistle-deferred-native-ritual-canceled.txt`,
  `/tmp/thistle-deferred-native-ritual-recast.txt`,
  `/tmp/thistle-deferred-native-ritual-offline.txt`, and
  `/tmp/thistle-deferred-server-acceptance.log`.

Validation commands: `mix test.all`, `mix compile --warnings-as-errors`,
`mix credo --strict`, `mix format --check-formatted`, and `git diff --check`.
