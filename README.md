# thistle tea

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/pikdum/thistle_tea)

wip vanilla private server written in elixir

## contributing

i've had a lot of fun hacking on this and it would be neat if you did too

hop in the [discord](https://discord.gg/dSYsRXHDhb) if you're interested in helping out

## running

```bash
# need elixir, a C++ compiler, and ~/code/namigator checked out
git clone https://github.com/pikdum/thistle_tea.git
cd thistle_tea
mix deps.get
mix deps.compile

# need npm or bun or similar
cd assets && npm install && cd ../

# with nix, no docker
nix run .#vmangos-db -- ./db

# path to vanilla client, the directory with WoW.exe
# you'll want version 1.12.1 build 5875
# this is only for generating dbc.sqlite
export WOW_DIR="/path/to/vanilla/client"

# need docker
./scripts/generate-dbc-db.sh

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
- **dbc.sqlite** `./scripts/generate-dbc-db.sh`
  - need to generate from wow client, since this can't be distributed
  - this has spell info and similar

### nix (no docker)

alternative to the scripts above. needs nix with flakes enabled. all upstreams
(VMangos/core, mangoszero/server, gtker/wow_dbc, vdechef/mysql2sqlite)
are pinned in `flake.lock`; bump them with `nix flake update`.

```bash
# generates db/vmangos.sqlite
nix run .#vmangos-db -- ./db

# generates db/dbc.sqlite from your local wow 1.12 client
nix run .#dbc-db -- "/path/to/vanilla/client" ./db
```

individual targets if you just want the tools on PATH:

```bash
nix build .#mangos-map-extractor   # map-extractor, vmap-extractor, mmap-extractor
nix build .#wow-dbc-converter      # wow_dbc_converter
nix develop .#wow-tools            # shell with all of the above + sqlite + mariadb
```

## what (somewhat) works

- logging in
- creating characters
- entering world
- seeing other players
- chatting
- mob spawns/respawns
- casting spells
- auto-attacks
- mob navigation

## helpful resources

- [idewave](https://github.com/idewave/idewave-core) - reference implementation
- [mangos](https://github.com/mangoszero/server/) - reference implementation
- [VMangos](https://github.com/vmangos/core) - world database
- [mysql2sqlite](https://github.com/vdechef/mysql2sqlite) - convert world database to sqlite
- [shadowburn](https://shadowburn-project.org/) - auth crypto + reference implementation
- [wow_dbc_converter](https://github.com/gtker/wow_dbc/tree/main/wow_dbc_converter) - convert dbc to sqlite
- [wow_messages](https://gtker.com/wow_messages/) - packet structure
- [wowdev](https://wowdev.wiki/Main_Page) - documentation
