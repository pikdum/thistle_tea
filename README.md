# thistle_tea

vanilla private server

## what (somewhat) works

- logging in
- creating characters
- entering world
- seeing other players
- chatting
- mob spawns/respawns
- casting spells
- auto-attacks

## helpful resources

- [idewave](https://github.com/idewave/idewave-core) - reference implementation
- [mangos](https://github.com/mangoszero/server/) - reference implementation
- [mangos database](https://github.com/mangoszero/database) - world database
- [mysql2sqlite](https://github.com/vdechef/mysql2sqlite) - convert world database to sqlite
- [shadowburn](https://shadowburn-project.org/) - auth crypto + reference implementation
- [wow_dbc_converter](https://github.com/gtker/wow_dbc/tree/main/wow_dbc_converter) - convert dbc to sqlite
- [wow_messages](https://gtker.com/wow_messages/) - packet structure
- [wowdev](https://wowdev.wiki/Main_Page) - documentation

## running

```bash
# need elixir
git clone https://github.com/pikdum/thistle_tea.git
cd thistle_tea
mix deps.get

# need docker + expect + no running mysql/mariadb
./scripts/generate-mangos0-db.sh
# or, just download it
# wget https://pomf2.lain.la/f/jxcam7ob.sqlite -O ./db/mangos0.sqlite

# need a vanilla wow client, this is directory with WoW.exe
# this is only for generating dbc.sqlite
# also, change server to localhost in realmlist.wtf
export WOW_DIR="/path/to/vanilla/client"

# need docker
./scripts/generate-dbc-db.sh

iex -S mix
# default logins are in application.ex
# test:test
```

## required databases

- **mangos0.sqlite** `./scripts/generate-mangos0-db.sh`
  - can generate or download
- **dbc.sqlite** `./scripts/generate-dbc-db.sh`
  - need to generate from wow client, since this can't be distributed
