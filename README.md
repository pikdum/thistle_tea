# thistle_tea

vanilla private server

## what (somewhat) works

- logging in
- creating characters
- entering world
- seeing other players
- chatting
- mob spawns

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

- need world database (mangos0.sqlite) and dbc database (vanilla_dbcs.sqlite)
- world database is created from mangos dump + mysql2sqlite
  - `./mysql2sqlite mangos0-dump.sql | sqlite3 mangos0.sqlite`
- dbc database is created from wow_dbc_converter
  - `./wow_dbc_converter vanilla -i ~/code/wowfiles/dbc/ -o ~/code/wowfiles/out/`
