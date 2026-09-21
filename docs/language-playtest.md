# Spoken languages

Players can speak languages granted by their learned spell effects. Chat now
validates the requested language before routing it; an unlearned language
produces the native notification, and malformed language or audience values
are discarded. Ordinary speech cannot request universal or addon language to
bypass comprehension. Valid addon traffic keeps its protocol language and
never executes development commands.

DBC effect 39 loads as `:language`, and aura 75 loads as `:mod_language`.
Curse of Tongues changes outgoing speech to Demonic without teaching that
language. Resolution reads the active aura holders, so dispelling, expiry,
death, and removal restore the remaining override or normal language.
Whispers, emotes, and availability messages remain universally readable
after validation. This change does not add guild chat or cross-faction
whisper restrictions.

Language skills supply native comprehension at 300/300. Learning and forgetting
spells update these skills, retain them through the runtime character store,
and mark player fields for publication. No disk persistence was added.

References: language validation and overrides in
`refs/vmangos/src/game/Handlers/ChatHandler.cpp`, readable whispers in
`refs/vmangos/src/game/Chat/MasterPlayerChat.cpp`, language effects in
`refs/vmangos/src/game/Spells/SpellEffects.cpp`, and language skill mappings in
`refs/vmangos/src/game/ObjectMgr.cpp`.

## Automated validation

- `mix test.all`: **4,379 passed**.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.

Tests cover learned capabilities and removal, permitted chat audiences,
forged universal speech, addon preservation and command isolation, notification
serialization, nearby recipient packets, whisper readability, curse cleanup,
and overlapping language overrides. DBC tests verify racial language effects,
Curse of Tongues, non-racial language learning, and immediate learning/removal
publication with retained character state.

Logs: `/tmp/thistle-language-publication-{all,compile,credo}.log`.

## Native client acceptance

Used isolated build-5875 clients with level-50 Debugwarlock (Human, GUID 6),
Debugbidder (Human Mage, GUID 11), and Debughunter (Dwarf, GUID 7), on map 451.
God mode was off. Curse casts and removal used normal client spell actions
during a duel. Existing `.go xyz` and `.learn 672` commands handled staging
and language learning. Tidewave probes only read live state.

| Scenario | Observed result |
| --- | --- |
| Common baseline | Both Humans read the original sentence, "bright lanterns guide the caravan". |
| Curse of Tongues 11719 | The Mage's Common speech arrived as scrambled Demonic. The live holder had about 19 seconds remaining, and the server resolved Common to language 8. |
| Whisper while cursed | The Warlock read the Mage's original private message. |
| Remove Lesser Curse 475 | The Mage removed the curse before expiry. Common speech became readable again, the holder cleared, and language resolution returned 7. |
| Natural expiry | A second curse expired after its 30-second duration. The holder cleared and Common speech became readable again. |
| Racial languages | The Dwarf spoke Common and Dwarvish. The Human Mage understood Common and saw scrambled Dwarvish; the Dwarf saw the original text. |
| Unlearned language | The Human Mage sent a valid native Dwarvish request before learning it. The server rejected it with "You have not learned that language." |
| Immediate learning | After `.learn 672`, an idle Human Mage understood the next Dwarvish sentence immediately, without movement or reconnecting. The client displayed the acquired language skill, and the server held skill 111 at 300/300. The Mage could also send Dwarvish. |
| Reconnect | The Mage logged out and back in, retained skill 111 at 300/300, and continued to understand the original Dwarvish text. |

The native runs found two bugs that were fixed before acceptance: non-racial
language learning skipped the comprehension skill because its DBC row had a
nonzero tier, and non-aura spell learning did not request a player field update.
The second bug left an idle client unable to understand its new language until
reconnecting. The final fresh run verified immediate comprehension on
`1b9d0e6d`; the curse and racial-language scenarios were exercised on
`65e861dc`, and the server notification on `91bc45c9`.

Language unlearning, death cleanup, overlapping overrides, and addon edge cases
were covered by automated tests. No gameplay owner errors or cast validation
failures appeared in the three native server logs. Existing unimplemented
account-data, raid-info, GM-ticket, and meeting-stone notifications remain.

## Retained evidence

- Server logs: `/tmp/thistle-language-server.log`,
  `/tmp/thistle-language-final-server.log`, and
  `/tmp/thistle-language-publication-server.log`.
- Curse and racial probes:
  `/tmp/thistle-language-{before,cursed,cleansed,expiry-active,expired,racial}.txt`.
- Final learning probes:
  `/tmp/thistle-language-publication-{before,learned,reconnected}.txt`.
- Curse screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.uZidzG/screenshots/`, including
  `language-before.png`, `language-cursed.png`, `language-cleansed.png`,
  `language-expired.png`, and `language-racial-sender.png`.
- Racial listener screenshot:
  `/home/pikdum/.cache/thistle-wow-playtest.Y2faCN/screenshots/language-racial-listener.png`.
- Server rejection screenshot:
  `/home/pikdum/.cache/thistle-wow-playtest.X12pTP/screenshots/language-server-rejected.png`.
- Final learning screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.B58xy7/screenshots/`, including
  `language-before-learning.png`, `language-immediate-learning.png`, and
  `language-reconnected.png`.

All helper-owned clients, displays, and native test servers were stopped after
acceptance. No changes were pushed.
