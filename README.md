# thistle tea

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/pikdum/thistle_tea)

wip vanilla private server written in elixir

## contributing

i've had a lot of fun hacking on this and it would be neat if you did too

hop in the [discord](https://discord.gg/dSYsRXHDhb) if you're interested in helping out

## running

```bash
# the devenv shell provides elixir, a C++ toolchain, and namigator (NAMIGATOR_SRC);
# outside devenv, point NAMIGATOR_SRC at a namigator checkout
git clone https://github.com/pikdum/thistle_tea.git
cd thistle_tea
mix deps.get
mix deps.compile

# need npm or bun or similar
cd assets && npm install && cd ../

# generate db/vmangos.sqlite (mobs, items, etc.)
cachix use thistle-tea
nix run .#vmangos-db -- ./db

# path to vanilla client, the directory with WoW.exe
# you'll want version 1.12.1 build 5875
# this is only for generating dbc.sqlite + maps
export WOW_DIR="/path/to/vanilla/client"

# generate db/dbc.sqlite (spell info, etc.) from the client
nix run .#dbc-db -- "$WOW_DIR" ./db

# generate navigation meshes from the client (takes a while)
nix run .#maps -- "$WOW_DIR"

# if not localhost, set GAME_SERVER:
# GAME_SERVER=192.168.1.110 iex -S mix
iex -S mix
# change server to localhost in realmlist.wtf
# default logins are in application.ex (test:test)
# also, there's a test server at 150.230.28.221
```

More documentation, like platform-specific setup guides, can be found in the [Wiki](https://github.com/pikdum/thistle_tea/wiki).

## databases

- **vmangos.sqlite** `nix run .#vmangos-db -- ./db`
  - generated from the pinned VMangos SQLite snapshot in `flake.nix`
  - this has mobs, items, etc.
- **dbc.sqlite** `nix run .#dbc-db -- "$WOW_DIR" ./db`
  - generated from your local wow 1.12 client, since it can't be distributed
  - this has spell info and similar

upstreams (VMangos/core, mangoszero/server, gtker/wow_dbc, vdechef/mysql2sqlite,
pikdum/namigator) are pinned in `flake.lock`; bump them with `nix flake update`.

individual targets if you just want the tools on PATH:

```bash
nix build .#mangos-map-extractor   # map-extractor, vmap-extractor, mmap-extractor
nix build .#wow-dbc-converter      # wow_dbc_converter
nix build .#namigator-mapbuilder   # MapBuilder (navmesh generation)
nix develop .#wow-tools            # shell with all of the above + sqlite + mariadb
```

## what (somewhat) works

- logging in + creating characters
- entering world + seeing other players
- chatting, channels, and parties
- mob spawns, combat, navigation, and respawns
- auto-attacks + class abilities
- ground mounts, mounted speed bonuses, and dismounting on cancellation or swimming
- parry haste for player and mob melee swings, including dual-wield timing
- main-hand disarm: unarmed player combat, armed-creature damage reduction, weapon ability checks, and off-hand preservation
- rear-hit daze from uncontrolled creatures, with level and defense-skill scaling
- mechanic resistance for spells and melee abilities, including Orc Hardiness
- exclusive resistance buffs use the strongest effect per school, with weaker protection resuming on removal
- crowd-control diminishing returns, shared across casters with recovery after control ends
- Priest Fade: temporary threat reduction with target switching and restoration on expiry
- Rogue Distract: ground-targeted facing and timed patrol pauses, preserving stealth
- pets
- typed invisibility and detection, with observer visibility, creature aggro, and action interruption
- items, bags, equipment, and vendors
- alcohol intoxication, client drunkenness effects, gradual sobering, and death cleanup
- looting + group loot
- quests
- xp, leveling, and exploration
- isolated dungeon instances (Ragefire Chasm)
- Deadmines boss doors and gunpowder cannon breach, with Smite's alarms and pirate response
- dying + resurrecting
- Soulstones and Reincarnation, with reagent consumption, cooldowns, and talent modifiers
- fall damage, Safe Fall, and Slow Fall protection
- underwater breath timers, drowning, water-breathing effects, and extended breath reserves
- swimming speed bonuses and snare updates, synchronized with the player and nearby observers
- gossip + trainers
- chests, fishing, and chairs
- resource tracking for herbs, minerals, and treasure, with exclusive tracking modes
- mail

## helpful resources

- [idewave](https://github.com/idewave/idewave-core) - reference implementation
- [mangos](https://github.com/mangoszero/server/) - reference implementation
- [VMangos](https://github.com/vmangos/core) - world database
- [mysql2sqlite](https://github.com/vdechef/mysql2sqlite) - convert world database to sqlite
- [shadowburn](https://shadowburn-project.org/) - auth crypto + reference implementation
- [wow_dbc_converter](https://github.com/gtker/wow_dbc/tree/main/wow_dbc_converter) - convert dbc to sqlite
- [wow_messages](https://gtker.com/wow_messages/) - packet structure
- [wowdev](https://wowdev.wiki/Main_Page) - documentation
