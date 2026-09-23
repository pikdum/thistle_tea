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
- [Spoken languages](docs/language-playtest.md), with learned comprehension, racial languages, Curse of Tongues, readable whispers, and immediate skill updates
- [Friends and ignore lists](docs/social-playtest.md), with offline contacts, live presence, reconnect retention, chat filtering, and invitation restrictions
- [Raid groups](docs/raid-playtest.md), with 40-member rosters, assistants, subgroups, target markers, ready checks, raid chat, subgroup buffs, and quest eligibility
- [AFK and DND status](docs/chat-status-playtest.md), with public tags, whisper echoes and automatic replies, reconnect cleanup, and AFK battleground departure
- [Emotes and posture](docs/emote-playtest.md), with DBC animations, persistent poses, movement and channel interruption, and Feign Death and pet-control cleanup
- mob spawns, combat, navigation, and respawns
- auto-attacks + class abilities
- [Combo point builders](docs/combo-points-playtest.md), with Premeditation expiry, talent-generated points, finisher consumption, and single melee proc delivery
- [Ownerless summoned objects](docs/wild-object-playtest.md), with shared loot, caster-independent lifetimes, linked objects, and environmental trap activation
- creature-specific melee and ranged attack power from slaying gear and consumables, with weapon-speed scaling and live target debuffs
- [Armor and spell penetration](docs/resistance-penetration-playtest.md), with school masks, stacking, equipment bonuses, and periodic damage
- school-based spell cost reductions, with stacking, client cost displays, and free casts
- percentage base-stat bonuses and penalties, including world buffs and Resurrection Sickness, with layered stacking and death-persistent aura expiry
- independent mana and energy regeneration across Druid forms, with the five-second rule, Reflection, and Innervate
- ground mounts, mounted speed bonuses, and dismounting on cancellation or swimming
- parry haste for player and mob melee swings, including dual-wield timing
- shield block value from equipment, enchants, and percentage talents, shared by defensive blocks and Shield Slam
- learned parry and block capabilities, weapon and shield requirements, sheath restrictions, and defense-skill avoidance on the character sheet
- [Combat skill progression](docs/combat-skills-playtest.md), with shared weapon bonuses, off-hand and ranged training, resolved outcome checks, and launch-time weapon attribution
- [Weapon attack accuracy](docs/attack-accuracy-playtest.md), with dual-wield miss penalties, queued-attack suppression, hit scaling, PvP defense, and capped glancing adjustments
- [Weapon-dependent offensive bonuses](docs/weapon-bonuses-playtest.md), with per-hand hit, weapon talents and enchants, skill-derived crit displays, and filtered white-attack damage
- [Extra attacks](docs/extra-attacks-playtest.md), with pending melee batches, proc recursion guards, swing timing, combat-log feedback, and lifecycle cleanup
- [Melee readiness](docs/melee-readiness-playtest.md), with shared facing and control checks, per-hand retries, dual-wield swing separation, and native error feedback
- [Blocked-hit procs](docs/blocked-hit-procs-playtest.md), with combined block and absorb outcomes, Retaliation, damage-shield contact rules, and incoming proc cooldowns
- [Cast-completion procs](docs/cast-completion-procs-playtest.md), with Elemental Focus, separate cast and hit phases, spell/ability classification, and caster-proc suppression
- [Stacking spell trinkets](docs/stacking-spell-trinkets-playtest.md), with temporary spell-power snapshots, Unstable Power's diminishing bonus, Ascendance's increasing bonus, and linked aura cleanup
- [Direct damage aura procs](docs/direct-proc-damage-playtest.md), with Flameblade, Holy Shield, carrier attribution, inherited rank rules, and charge exhaustion
- main-hand disarm: unarmed player combat, armed-creature damage reduction, weapon ability checks, and off-hand preservation
- rear-hit daze from uncontrolled creatures, with level and defense-skill scaling
- mechanic resistance for spells and melee abilities, including Orc Hardiness
- aura-state and spell-effect immunities, with partial spell blocking, control purges, and expiry cleanup
- school-specific damage immunity, with melee and periodic immune feedback and spell bypass attributes
- [Binary spell resistance](docs/binary-spells-playtest.md), with all-or-nothing control spells, school penetration, full-hit damage, triggered casts, and resistance lifecycle updates
- [Triggered spell hits](docs/triggered-spell-hits-playtest.md), with per-target hit rolls, original-caster modifiers, saved impact outcomes, channel target retention, and cancellation
- [Wounded creature movement](docs/wounded-creatures-playtest.md), with low-health running penalties, pet and boss exemptions, active path retiming, snare composition, and recovery
- periodic mana drains and life leech, with transfers limited by available mana and actual health lost
- healing suppression and amplification across direct heals and HoTs, with strongest-effect stacking and live expiry updates
- stack-aware dispels, with partial cures, Dispel All categories, and client combat-log feedback
- talent-based dispel resistance, including Vile Poisons, per-stack attempts, and failed-dispel feedback
- general and school-specific spell reflection, including Sheen of Zanza's guaranteed first reflection and charge consumption
- [Grounding Totem and spell magnets](docs/grounding-totem-playtest.md), with shared interception charges, periodic protection, and totem immunity and destruction cleanup
- spell modifiers use VMangos family masks, including all 64 bits, to affect only the intended abilities
- stacked damage-over-time effects scale with remaining stacks after partial cures
- exclusive resistance buffs use the strongest effect per school, with weaker protection resuming on removal
- crowd-control diminishing returns, shared across casters with recovery after control ends
- [Pacification and silence](docs/combat-control-playtest.md), including combined controls, attack suppression, channel interruption, and overlapping-source cleanup
- creature and pet fear movement, with bounded panic runs, control cleanup, and Curse of Recklessness suppression
- [Critter escape behavior](docs/critter-playtest.md), with damage and debuff reactions, timed panic movement, combat recovery, and death cleanup
- [Creature combat defaults](docs/creature-flags-playtest.md), with template immunity, invincibility, defense rules, stationary behavior, and script overrides
- [Creature-group combat](docs/creature-groups-playtest.md), with shared aggro, evade, respawn, death notifications, scripted membership, and group conditions
- [Creature formations](docs/creature-formations-playtest.md), with coordinated patrol movement, temporary leaders, inherited waypoint routes, and return-to-formation behavior
- [Shared creature leashes](docs/creature-leashes-playtest.md), with combat origins, assistance clocks, hostile-contact extensions, and return-home cleanup
- [Creature-owned summon clocks](docs/creature-owner-leashes-playtest.md), with owner inheritance, idle-owner links, lethal-hit extensions, and independent lifecycle cleanup
- [Creature-owned combat pets](docs/creature-pets-playtest.md), with a single monitored pet slot, aggressive combat, dead-pet replacement, and cleanup alongside independent guardians
- [Player fear and confusion](docs/player-control-movement-playtest.md), with forced movement, client control restoration, bounded wandering, teleport recovery, and death cleanup
- [Spell knockback](docs/knockback-playtest.md), with acknowledged launches, observer movement, cast interruption, possession routing, and landing cleanup
- [Spell-driven player pulls](docs/player-pull-playtest.md), with ballistic trajectories, height compensation, cast interruption, acknowledged movement, and observer playback
- [Spell-driven taxi flights](docs/spell-taxi-playtest.md), with validated routes, form cleanup, accurate landing points, protected passengers, and native flight and relog acceptance
- [Taxi flight resumption](docs/taxi-resumption-playtest.md), with stationary offline checkpoints, reconnect continuation, stale callback rejection, and pet restoration on landing
- Priest Fade: temporary threat reduction with target switching and restoration on expiry
- Rogue Distract: ground-targeted facing and timed patrol pauses, preserving stealth
- Hunter Beast Lore: caster-specific beast damage, armor, and resistance information, with expiry and death cleanup
- [Detect Magic](docs/detect-magic-playtest.md), with enemy buff revelation, live buff updates, and dispel, expiry, and death cleanup
- pets
- [Noncombat critter companions](docs/mini-pet-playtest.md), with separate ownership, following, item toggles, replacement, creation passives, and lifecycle cleanup alongside combat pets
- [Autonomous guardians](docs/guardian-playtest.md), with multiple summons, Engineering scaling, combat and following, creature stat buffs, and monitored lifetime cleanup alongside combat pets
- [Wild creature summons](docs/wild-summon-playtest.md), with independent lifetimes, Target Dummy taunts and salvage, timed death and corpse cleanup, and usable Field Repair Bots
- [Hunter pet happiness](docs/pet-happiness-playtest.md): feeding, timed decay, damage tiers, death penalties, and retained state across dismissal and reconnect
- [Hunter pet experience](docs/pet-experience-playtest.md): kill rewards, level growth, owner-level caps, and retained progress, learned abilities, and reaction stance
- [Hunter pet loyalty](docs/pet-loyalty-playtest.md): happiness-based bonding, training-point earnings, rank loss, and runaway cleanup, retained through dismissal and reconnect
- [Hunter pet training](docs/pet-training-playtest.md): ability purchases, rank-upgrade credits, passive stat bonuses, family and level checks, and retained learned spells
- [Hunter pet stables](docs/pet-stable-playtest.md): two purchased slots, storage and swaps, persistent pet identity, and retained health and progression
- typed invisibility and detection, with observer visibility, creature aggro, and action interruption
- observer-specific stealth detection, with Perception, Paranoia, Track Hidden, facing, line of sight, and caster-specific Hunter's Mark
- items, bags, equipment, and vendors
- [Spell item transformation](docs/item-transformation-playtest.md), with atomic same-slot replacement, retained enchants and wear, shared cooldowns, and full-inventory support
- [Vendor buyback](docs/vendor-buyback-playtest.md), with 12 session slots, partial-stack sales, preserved item state, charge and durability pricing, paused timers, and logout cleanup
- [Limited vendor stock](docs/vendor-stock-playtest.md), shared between buyers at each merchant, with timed restocking, template inventories, sold-out feedback, and recoverable purchases
- [Ammunition](docs/ammunition-playtest.md), with client selection, compatible projectile costs, Auto Shot depletion, and thrown-stack or durability consumption
- [Wand attacks](docs/wand-playtest.md), with weapon-school damage, Wand Specialization, and shared auto-repeat timing and cancellation
- [Creature and pet attack power](docs/attack-power-playtest.md), with damage scaling, buff and debuff cleanup, percentage modifiers, and ranged equipment bonuses
- [Passive on-equip item spells](docs/equipment-passives-playtest.md), with crit, hit, dodge, mana regeneration, item procs, durability and reconnect lifecycles, and form restrictions
- [Learned defensive capabilities](docs/defensive-capabilities-playtest.md), with Shaman Parry talent learning and reset, defense skill projection, weapon requirements, sheath restrictions, and reconnect validation
- equipment durability, combat and death wear, broken-gear penalties, and vendor repairs with reputation discounts
- [Spell-driven durability](docs/spell-durability-playtest.md), with exact-slot and carried-gear wear, percentage damage, negative-point repairs, execution logs, and restored equipment effects
- alcohol intoxication, client drunkenness effects, gradual sobering, and death cleanup
- looting + group loot
- Rogue Pick Pocket, with private loot, quest drops, and failed-attempt retaliation
- Skinning, with corpse loot prerequisites, profession skill checks and gains, and private leather loot
- [Gathering and object locks](docs/gathering-playtest.md), with Mining, Herbalism, shared key and skill requirements, repeated vein harvests, and per-spawn skill gains
- [Spell focus requirements](docs/spell-focus-playtest.md), with forges, anvils, cooking fires, alchemy labs, native errors, and revalidation before casting costs
- [Spell-granted skill ranks](docs/spell-skills-playtest.md), with profession starter recipes, preserved progress on rank upgrades, riding values, and abandonment cleanup
- [Teaching spells and recipe books](docs/spell-teaching-playtest.md), with recipe learning, Expert profession books, atomic consumption, cancellation, and specialization requirements
- [Inventory containers and lockboxes](docs/item-containers-playtest.md), with retained private loot, Pick Lock, consumable keys, atomic claims, and full-bag recovery
- [Trade-slot unlocking](docs/trade-opening-playtest.md), with paid lockpicking, consumable keys, final requirement checks, and retry without closing the trade
- [Wrapped gifts](docs/gift-wrapping-playtest.md), with atomic paper consumption, creator labels, and retained item identity, charges, and enchants through trade and opening
- [Timed items](docs/item-duration-playtest.md), with client countdowns, offline lifetime rules, conjured-item cleanup, and expiration across equipment, bags, and bank storage
- Disenchanting, with exact-item consumption, private material loot, Enchanting skill gains, and recovery when bags are full
- Permanent equipment enchants, with atomic material costs, profession skill gains, independent equipment bonuses, and weapon procs
- [Charged weapon coatings](docs/weapon-coatings-playtest.md), with finite poison charges, proc chance talents, atomic application, and depletion cleanup
- [Creature-specific flat damage](docs/creature-damage-playtest.md), including Beastslayer and Elemental Slayer enchants across weapon attacks, spells, and periodic damage
- quests
- [Quest dependencies](docs/quest-dependencies-playtest.md), with signed and alternative prerequisites, exclusive groups, chains, breadcrumbs, profession requirements, and live NPC marker refreshes
- [Quest sharing](docs/quest-sharing-playtest.md), with party confirmations, eligibility feedback, inherited timers, source-item lifecycle, and stale-offer cleanup
- [Item-started quests](docs/item-quests-playtest.md), with owned starter validation, atomic item exchanges, retained objectives, full-bag rejection, and party confirmation
- [Game-object questgivers](docs/game-object-quests-playtest.md), with per-player activation, native quest chains, conditioned gossip, and scripted player casts
- xp, leveling, and exploration
- [Rested experience and logout](docs/rest-logout-playtest.md), with offline inn and wilderness gains, idle rest updates, native logout countdowns, and cancellation cleanup
- isolated dungeon instances (Ragefire Chasm)
- Deadmines boss doors and gunpowder cannon breach, with Smite's alarms and pirate response
- dying + resurrecting
- Soulstones and Reincarnation, with reagent consumption, cooldowns, and talent modifiers
- fall damage, Safe Fall, and Slow Fall protection
- [Environmental fire damage](docs/environmental-fire-playtest.md), with world campfires, resistance, shield depletion, combat-log feedback, and death durability loss
- underwater breath timers, drowning, water-breathing effects, and extended breath reserves
- swimming speed bonuses and snare updates, synchronized with the player and nearby observers
- gossip + trainers
- [Innkeeper home binding](docs/home-binding-playtest.md), with confirmation, retained home locations, Hearthstones, Astral Recall, and replacement Hearthstones
- chests, fishing, and chairs
- resource tracking for herbs, minerals, and treasure, with exclusive tracking modes
- mail
- [Auction houses](docs/auction-playtest.md), with linked faction markets, neutral auctions, bids, buyout, cancellation, expiry, exact-item escrow, and recoverable mail settlement

## helpful resources

- [idewave](https://github.com/idewave/idewave-core) - reference implementation
- [mangos](https://github.com/mangoszero/server/) - reference implementation
- [VMangos](https://github.com/vmangos/core) - world database
- [mysql2sqlite](https://github.com/vdechef/mysql2sqlite) - convert world database to sqlite
- [shadowburn](https://shadowburn-project.org/) - auth crypto + reference implementation
- [wow_dbc_converter](https://github.com/gtker/wow_dbc/tree/main/wow_dbc_converter) - convert dbc to sqlite
- [wow_messages](https://gtker.com/wow_messages/) - packet structure
- [wowdev](https://wowdev.wiki/Main_Page) - documentation
