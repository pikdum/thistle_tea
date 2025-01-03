# thistle tea

wip vanilla private server written in elixir

## contributing

i've had a lot of fun hacking on this and it would be neat if you did too

hop in the [discord](https://discord.gg/dSYsRXHDhb) if you're interested in helping out

## running

```bash
# need elixir + cargo
git clone https://github.com/pikdum/thistle_tea.git
cd thistle_tea
mix deps.get
mix deps.compile

# need npm or bun or similar
cd assets && npm install && cd ../

# need docker + no mariadb port 3306 conflict
./scripts/generate-mangos0-db.sh
# or, just download it
# wget https://pomf2.lain.la/f/jxcam7ob.sqlite -O ./db/mangos0.sqlite

# path to vanilla client, the directory with WoW.exe
# you'll want version 1.12.1 build 5875
# this is only for generating dbc.sqlite + maps
export WOW_DIR="/path/to/vanilla/client"

# need docker
./scripts/generate-dbc-db.sh

# this takes a very long time
# probably 30+ minutes
mix build_maps

# if not localhost, set GAME_SERVER:
# GAME_SERVER=192.168.1.110 iex -S mix
iex -S mix
# change server to localhost in realmlist.wtf
# default logins are in application.ex (test:test)
# also, there's a test server at 150.230.28.221
```

## databases

- **mangos0.sqlite** `./scripts/generate-mangos0-db.sh`
  - can generate or download
  - this has mobs, items, etc.
- **dbc.sqlite** `./scripts/generate-dbc-db.sh`
  - need to generate from wow client, since this can't be distributed
  - this has spell info and similar

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
- [mangos database](https://github.com/mangoszero/database) - world database
- [mysql2sqlite](https://github.com/vdechef/mysql2sqlite) - convert world database to sqlite
- [shadowburn](https://shadowburn-project.org/) - auth crypto + reference implementation
- [wow_dbc_converter](https://github.com/gtker/wow_dbc/tree/main/wow_dbc_converter) - convert dbc to sqlite
- [wow_messages](https://gtker.com/wow_messages/) - packet structure
- [wowdev](https://wowdev.wiki/Main_Page) - documentation

## For Mac Users

If you use a Mac with Intel chip I think you can use [Wine](https://www.winehq.org/) (as long as it supports 32-bit programs)

For all the mac users that run with an Apple Silicon Wine is not an option. I strongly suggest to use a Virtual Machine with Windows.

Here's what I did to run Wow on a M1 Macbook pro: 

1. Download and install [VMware Fusion](https://blogs.vmware.com/teamfusion/2024/05/fusion-pro-now-available-free-for-personal-use.html) (it's free for personal use so you don't have to pay for Windows license)
2. Download a Wow Vanilla Client (I used this [site](https://zremax.com/blog/vanilla-wow-client-download)) on your host and execute **ALL** the setup commands on your host (some of them needs a wow folder).
3. Move the Wow folder from your host to the Virtual Machine
4. Then Go to Vmware fusion > Virtual Machine > Network Adapter > Host only (this way your virtual machine will only connect to your host)
5. On your host open a terminal and type `ifconfig` and look at your host IP address (probably under **bridge100** or something like that, and should be something like 192.168.X.X )
6. Inside the folder of your Wow client change the realmist to `set realmist <YOUR_HOST_IP_ADDRESS>`
7. Run the Elixir server on your host
8. Open your Wow client on your Virtual machine and your good to go!