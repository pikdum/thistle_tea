# Flare and independent ground effects

Validated on 2026-09-25 with two native build-5875 clients against the local server.

## Shared implementation

Dispel immunity now purges existing holders with the matching dispel type when
the immunity spell carries `immunity_purges_effect`. Removal passes through the
normal aura transition, including concealment flags and visibility publication.

Each ground aura effect retains its own `PersistentArea` source. Separately
delivered effects of the same spell and caster coexist in one holder. Leaving,
cancelling, or expiring one source removes only its effect. Overlapping sources
of the same effect retain the existing contribution until it ends. Periodic
effects retain their source schedule and receive independent hit rolls.

The references are `Unit::ApplySpellDispelImmunity`,
`DynamicObjectUpdater::VisitHelper`, and `PersistentAreaAura::Update` in
`refs/vmangos`. Flare (1543) supplies two persistent-area dispel immunities:
stealth (5) and invisibility (6).

## Native acceptance

Debughunter (GUID 7) and Debugbidder (GUID 11) dueled near Northshire at
`{-8944, -132, 83.5}` and `{-8949, -132, 83.5}` on open map 0. The existing
development commands taught Flare, Lesser Invisibility (66), and Stealth (1784).
The mage learned Stealth for this test. God mode was disabled before acceptance.
All casts, ground clicks, movement, and logout actions came from the clients;
Tidewave probes only observed state and messages.

Verified behavior:

- Lesser Invisibility removed the mage from the hunter's tracked entities and
  set the mage's invisibility flag to 64. Casting Flare revealed the model,
  cleared concealment, and retained both immunity effects in one holder with
  two distinct ground sources.
- An invisibility cast inside Flare displayed `Immune` and failed validation
  with `:immune`, leaving the target visible.
- Stealth set the player flag to 32 and the unit creep flag to 2, hiding the
  mage from the hunter. Flare removed the complete stealth holder and both
  flags. After the normal stealth cooldown, another attempt inside Flare
  displayed `Immune` and failed validation with `:immune`.
- Walking to approximately `{-8921, -132, 80.85}` removed both immunities while
  the two ground objects remained active. Lesser Invisibility worked outside.
- In a separate run, the invisible mage walked backward into an active Flare.
  The owner lost invisibility, acquired both immunities, and became visible to
  the hunter again. Both players remained out of combat throughout that run.
- Natural expiry removed both ground objects and their recipient effects.
  Stealth then worked at the same location and hid the mage again.
- After ending the duel, the mage logged out and reconnected at the same
  location with no stale Flare holder or concealment flags.

An earlier sample showed a temporary hunter-only combat transition without
damage. A follow-up trace of combat entry functions and player callback returns
did not reproduce it; its cause remains unconfirmed. This is not counted as a
verified combat-rule fix.

## Evidence and validation

The isolated GPU sessions were
`/home/pikdum/.cache/thistle-wow-playtest.NwGh0s` and
`/home/pikdum/.cache/thistle-wow-playtest.RRlwQw`. Their `WoW.exe` processes used
`amdgpu`, with increasing graphics engine counters. Screenshots include
`flare-cursor`, `flare-revealed`, `invisibility-blocked`, `stealth-hidden`,
`stealth-revealed`, `stealth-immune`, `stealth-after-expiry`, and
`concealed-reentry-revealed`.

Local logs are `/tmp/thistle-flare-server.log`,
`/tmp/thistle-flare-packets.log`, and the state samples under
`/tmp/thistle-flare-*-state.log` and `/tmp/thistle-flare-*-sample.log`.
The packet trace recorded the real Flare and invisibility cast requests and
Flare's spell-go packets. The server recorded the expected immune validation
results, with no owner errors. Existing account-data, GM-ticket, and
meeting-stone unimplemented-message warnings appeared during login.

Both helper-owned client services were stopped and confirmed inactive. Both
players then had no entity process, metadata, or world position; the hunter's
Flare source registry was empty. The local server was stopped as well.

`mix test.all`: **6,147 passed**. Compilation with warnings as errors and strict
Credo both passed. Regression tests cover actual DBC Flare data, concealment
flags, distinct radii and expiry times, source cancellation, overlapping sources,
independent periodic hit rolls, final ticks, and concealed target discovery.
