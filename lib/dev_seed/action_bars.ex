defmodule ThistleTea.DevSeed.ActionBars do
  @moduledoc """
  Curated debug-character action bars resolved against each character's
  highest learned spell ranks.
  """

  @all_visible 0x0F
  @bar_starts %{
    main: 0,
    right: 24,
    right_2: 36,
    bottom_right: 48,
    bottom_left: 60,
    battle_stance: 72,
    cat_form: 72,
    defensive_stance: 84,
    bear_form: 96,
    berserker_stance: 96,
    stealth: 72
  }

  @layouts %{
    1 => [
      main: [
        "Attack",
        "Heroic Strike",
        "Cleave",
        "Rend",
        "Execute",
        "Hamstring",
        "Sunder Armor",
        "Slam",
        "Demoralizing Shout",
        "Battle Shout",
        "Bloodrage",
        "Intimidating Shout"
      ],
      battle_stance: [
        "Attack",
        "Heroic Strike",
        "Rend",
        "Charge",
        "Overpower",
        "Mocking Blow",
        "Thunder Clap",
        "Execute",
        "Hamstring",
        "Shield Bash",
        "Sunder Armor",
        "Mortal Strike"
      ],
      defensive_stance: [
        "Attack",
        "Heroic Strike",
        "Revenge",
        "Shield Block",
        "Shield Bash",
        "Shield Wall",
        "Disarm",
        "Sunder Armor",
        "Demoralizing Shout",
        "Challenging Shout",
        "Shield Slam",
        "Rend"
      ],
      berserker_stance: [
        "Attack",
        "Heroic Strike",
        "Cleave",
        "Execute",
        "Hamstring",
        "Intercept",
        "Pummel",
        "Whirlwind",
        "Berserker Rage",
        "Recklessness",
        "Sunder Armor",
        "Bloodthirst"
      ],
      bottom_left: [
        "Cleave",
        "Slam",
        "Battle Shout",
        "Demoralizing Shout",
        "Bloodrage",
        "Challenging Shout",
        "Intimidating Shout",
        "Berserker Rage",
        "Retaliation",
        "Perception"
      ],
      right: ["Battle Stance", "Defensive Stance", "Berserker Stance"]
    ],
    2 => [
      main: [
        "Attack",
        "Judgement",
        "Seal of Command",
        "Consecration",
        "Hammer of Justice",
        "Hammer of Wrath",
        "Exorcism",
        "Holy Shock",
        "Holy Shield",
        "Flash of Light",
        "Holy Light",
        "Cleanse"
      ],
      bottom_left: [
        "Holy Light",
        "Flash of Light",
        "Lay on Hands",
        "Divine Shield",
        "Divine Protection",
        "Blessing of Protection",
        "Blessing of Freedom",
        "Blessing of Sacrifice",
        "Cleanse",
        "Purify",
        "Redemption",
        "Divine Intervention"
      ],
      bottom_right: [
        "Blessing of Might",
        "Blessing of Wisdom",
        "Blessing of Light",
        "Blessing of Salvation",
        "Blessing of Sanctuary",
        "Blessing of Freedom",
        "Blessing of Protection",
        "Blessing of Sacrifice",
        "Righteous Fury"
      ],
      right: [
        "Devotion Aura",
        "Retribution Aura",
        "Concentration Aura",
        "Shadow Resistance Aura",
        "Frost Resistance Aura",
        "Fire Resistance Aura"
      ],
      right_2: [
        "Seal of Command",
        "Seal of Justice",
        "Seal of Light",
        "Seal of Righteousness",
        "Seal of Wisdom",
        "Seal of the Crusader",
        "Turn Undead",
        "Holy Wrath",
        "Perception"
      ]
    ],
    3 => [
      main: [
        "Auto Shot",
        "Aimed Shot",
        "Arcane Shot",
        "Multi-Shot",
        "Serpent Sting",
        "Scorpid Sting",
        "Viper Sting",
        "Hunter's Mark",
        "Rapid Fire",
        "Concussive Shot",
        "Distracting Shot",
        "Volley"
      ],
      bottom_left: [
        "Raptor Strike",
        "Wing Clip",
        "Mongoose Bite",
        "Counterattack",
        "Disengage",
        "Feign Death",
        "Flare",
        "Freezing Trap",
        "Frost Trap",
        "Explosive Trap",
        "Immolation Trap",
        "Scare Beast"
      ],
      bottom_right: [
        "Aspect of the Hawk",
        "Aspect of the Monkey",
        "Aspect of the Cheetah",
        "Aspect of the Pack",
        "Aspect of the Beast",
        "Aspect of the Wild",
        "Trueshot Aura",
        "Wyvern Sting",
        "Stoneform"
      ],
      right: [
        "Call Pet",
        "Dismiss Pet",
        "Revive Pet",
        "Mend Pet",
        "Feed Pet",
        "Eyes of the Beast",
        "Tame Beast",
        "Beast Lore"
      ],
      right_2: [
        "Track Beasts",
        "Track Demons",
        "Track Dragonkin",
        "Track Elementals",
        "Track Giants",
        "Track Hidden",
        "Track Humanoids",
        "Track Undead",
        "Find Treasure",
        "Eagle Eye"
      ]
    ],
    4 => [
      main: [
        "Attack",
        "Sinister Strike",
        "Backstab",
        "Eviscerate",
        "Slice and Dice",
        "Rupture",
        "Kidney Shot",
        "Gouge",
        "Kick",
        "Hemorrhage",
        "Throw",
        "Stealth"
      ],
      stealth: [
        "Attack",
        "Ambush",
        "Cheap Shot",
        "Garrote",
        "Sap",
        "Pick Pocket",
        "Backstab",
        "Eviscerate",
        "Slice and Dice",
        "Rupture",
        "Distract",
        "Vanish"
      ],
      bottom_left: [
        "Sprint",
        "Evasion",
        "Vanish",
        "Blind",
        "Distract",
        "Expose Armor",
        "Disarm Trap",
        "Feint",
        "Perception"
      ],
      bottom_right: [
        "Instant Poison IV",
        "Deadly Poison III",
        "Crippling Poison II",
        "Mind-numbing Poison II",
        "Wound Poison III",
        "Blinding Powder"
      ],
      right: ["Pick Lock", "Pick Pocket", "Disarm Trap", "Throw"]
    ],
    5 => [
      main: [
        "Shoot",
        "Smite",
        "Holy Fire",
        "Mind Blast",
        "Shadow Word: Pain",
        "Mind Flay",
        "Devouring Plague",
        "Starshards",
        "Mana Burn",
        "Psychic Scream",
        "Power Word: Shield",
        "Flash Heal"
      ],
      bottom_left: [
        "Lesser Heal",
        "Heal",
        "Greater Heal",
        "Flash Heal",
        "Renew",
        "Prayer of Healing",
        "Holy Nova",
        "Desperate Prayer",
        "Resurrection",
        "Dispel Magic",
        "Cure Disease",
        "Abolish Disease"
      ],
      bottom_right: [
        "Power Word: Fortitude",
        "Divine Spirit",
        "Inner Fire",
        "Shadow Protection",
        "Power Word: Shield",
        "Renew",
        "Levitate",
        "Elune's Grace",
        "Feedback",
        "Shadowguard",
        "Touch of Weakness"
      ],
      right: [
        "Mind Control",
        "Mind Soothe",
        "Mind Vision",
        "Shackle Undead",
        "Fade",
        "Hex of Weakness",
        "Perception"
      ],
      right_2: ["Lightwell"]
    ],
    7 => [
      main: [
        "Attack",
        "Lightning Bolt",
        "Chain Lightning",
        "Earth Shock",
        "Flame Shock",
        "Frost Shock",
        "Healing Wave",
        "Lesser Healing Wave",
        "Chain Heal",
        "Purge",
        "Ghost Wolf",
        "Blood Fury"
      ],
      bottom_left: [
        "Cure Disease",
        "Cure Poison",
        "Water Breathing",
        "Water Walking",
        "Ancestral Spirit",
        "Astral Recall",
        "Far Sight"
      ],
      bottom_right: [
        "Lightning Shield",
        "Rockbiter Weapon",
        "Flametongue Weapon",
        "Frostbrand Weapon",
        "Windfury Weapon",
        "Windfury Totem",
        "Grace of Air Totem",
        "Grounding Totem",
        "Nature Resistance Totem",
        "Windwall Totem",
        "Tranquil Air Totem",
        "Sentry Totem"
      ],
      right: [
        "Earthbind Totem",
        "Stoneclaw Totem",
        "Stoneskin Totem",
        "Strength of Earth Totem",
        "Tremor Totem",
        "Searing Totem",
        "Fire Nova Totem",
        "Magma Totem",
        "Flametongue Totem",
        "Fire Resistance Totem"
      ],
      right_2: [
        "Healing Stream Totem",
        "Mana Spring Totem",
        "Mana Tide Totem",
        "Disease Cleansing Totem",
        "Poison Cleansing Totem",
        "Frost Resistance Totem"
      ]
    ],
    8 => [
      main: [
        "Shoot",
        "Fireball",
        "Frostbolt",
        "Arcane Missiles",
        "Scorch",
        "Fire Blast",
        "Arcane Explosion",
        "Flamestrike",
        "Blizzard",
        "Cone of Cold",
        "Blast Wave",
        "Pyroblast"
      ],
      bottom_left: [
        "Polymorph",
        "Frost Nova",
        "Counterspell",
        "Blink",
        "Evocation",
        "Remove Lesser Curse",
        "Mana Shield",
        "Ice Barrier",
        "Fire Ward",
        "Frost Ward",
        "Slow Fall",
        "Detect Magic"
      ],
      bottom_right: [
        "Arcane Intellect",
        "Mage Armor",
        "Ice Armor",
        "Frost Armor",
        "Amplify Magic",
        "Dampen Magic",
        "Perception"
      ],
      right: [
        "Teleport: Darnassus",
        "Teleport: Ironforge",
        "Teleport: Orgrimmar",
        "Teleport: Stormwind",
        "Teleport: Thunder Bluff",
        "Teleport: Undercity",
        "Conjure Food",
        "Conjure Water",
        "Conjure Mana Jade",
        "Conjure Mana Citrine",
        "Conjure Mana Agate"
      ],
      right_2: [
        "Portal: Darnassus",
        "Portal: Ironforge",
        "Portal: Orgrimmar",
        "Portal: Stormwind",
        "Portal: Thunder Bluff",
        "Portal: Undercity"
      ]
    ],
    9 => [
      main: [
        "Shoot",
        "Shadow Bolt",
        "Immolate",
        "Corruption",
        "Siphon Life",
        "Curse of Agony",
        "Searing Pain",
        "Shadowburn",
        "Conflagrate",
        "Death Coil",
        "Drain Life",
        "Life Tap"
      ],
      bottom_left: [
        "Fear",
        "Howl of Terror",
        "Banish",
        "Enslave Demon",
        "Drain Mana",
        "Drain Soul",
        "Rain of Fire",
        "Hellfire",
        "Soul Fire",
        "Shadow Ward",
        "Dark Pact",
        "Health Funnel"
      ],
      bottom_right: [
        "Demon Armor",
        "Demon Skin",
        "Detect Greater Invisibility",
        "Unending Breath",
        "Sense Demons",
        "Perception"
      ],
      right: [
        "Summon Imp",
        "Summon Voidwalker",
        "Summon Succubus",
        "Summon Felhunter",
        "Inferno",
        "Eye of Kilrogg",
        "Ritual of Summoning"
      ],
      right_2: [
        "Create Healthstone (Greater)",
        "Create Soulstone (Greater)",
        "Create Firestone (Greater)",
        "Create Spellstone (Greater)",
        "Curse of Recklessness",
        "Curse of Shadow",
        "Curse of Tongues",
        "Curse of Weakness",
        "Curse of the Elements"
      ]
    ],
    11 => [
      main: [
        "Wrath",
        "Starfire",
        "Moonfire",
        "Insect Swarm",
        "Entangling Roots",
        "Faerie Fire",
        "Nature's Grasp",
        "Hurricane",
        "Hibernate",
        "Soothe Animal",
        "Healing Touch",
        "Rejuvenation"
      ],
      cat_form: [
        "Attack",
        "Claw",
        "Rake",
        "Shred",
        "Rip",
        "Ferocious Bite",
        "Pounce",
        "Ravage",
        "Cower",
        "Tiger's Fury",
        "Dash",
        "Prowl"
      ],
      bear_form: [
        "Attack",
        "Maul",
        "Swipe",
        "Demoralizing Roar",
        "Bash",
        "Enrage",
        "Frenzied Regeneration",
        "Challenging Roar",
        "Faerie Fire (Feral)"
      ],
      bottom_left: [
        "Healing Touch",
        "Regrowth",
        "Rejuvenation",
        "Tranquility",
        "Innervate",
        "Rebirth",
        "Remove Curse",
        "Abolish Poison",
        "Barkskin"
      ],
      bottom_right: [
        "Dire Bear Form",
        "Cat Form",
        "Aquatic Form",
        "Travel Form",
        "Mark of the Wild",
        "Thorns",
        "Nature's Grasp",
        "Shadowmeld"
      ],
      right: ["Track Humanoids", "Hibernate", "Soothe Animal", "Hurricane"]
    ]
  }

  def visible_toggles, do: @all_visible

  def build(class, learned_spells) when is_integer(class) and is_list(learned_spells) do
    highest_by_name = highest_by_name(learned_spells)

    @layouts
    |> Map.get(class, [])
    |> Enum.flat_map(&build_bar(&1, highest_by_name))
    |> Map.new()
  end

  def build(_class, _learned_spells), do: %{}

  defp highest_by_name(learned_spells) do
    Enum.reduce(learned_spells, %{}, fn spell, highest ->
      Map.update(highest, spell.name, spell, &higher_rank(&1, spell))
    end)
  end

  defp higher_rank(left, right) do
    if rank_key(left) >= rank_key(right), do: left, else: right
  end

  defp rank_key(spell), do: {spell.level || 0, spell.base_level || 0, spell.id}

  defp build_bar({bar, spell_names}, highest_by_name) do
    start = Map.fetch!(@bar_starts, bar)

    spell_names
    |> Enum.with_index(start)
    |> Enum.flat_map(fn {name, slot} ->
      case Map.get(highest_by_name, name) do
        nil -> []
        spell -> [{slot, spell.id}]
      end
    end)
  end
end
