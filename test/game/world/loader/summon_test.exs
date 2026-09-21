defmodule ThistleTea.Game.World.Loader.SummonTest do
  use ExUnit.Case, async: false

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.PetLevel
  alias ThistleTea.Game.Entity.Data.PetProgress
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.PetProgression
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.PetLevel, as: PetLevelLoader
  alias ThistleTea.Game.World.Loader.PetSpells
  alias ThistleTea.Game.World.Loader.PetTraining
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.Summon
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  setup do
    previous = PetLevelLoader.levels()

    stats = %PetLevel{
      level: 50,
      health: 2_215,
      armor: 3_018,
      strength: 113,
      agility: 82,
      stamina: 207,
      intellect: 43,
      spirit: 67,
      next_level_xp: 36_875
    }

    :ets.insert(PetLevelLoader, {:levels, %{50 => stats}})
    on_exit(fn -> :ets.insert(PetLevelLoader, {:levels, previous}) end)
    previous_profiles = :ets.lookup(PetSpells, {:profile, 2960})
    profile = %{spellbook: SpellLoader.build_spellbook([17_255, 24_604]), training_points: -14, recipes: %{}}
    :ets.insert(PetSpells, {{:profile, 2960}, profile})

    on_exit(fn ->
      :ets.delete(PetSpells, {:profile, 2960})
      :ets.insert(PetSpells, previous_profiles)
    end)

    :ok
  end

  describe "build_pet/2" do
    test "restores only family passives after untraining and retains the reset price history" do
      previous = :ets.lookup(PetTraining, {:family_passives, 1})
      family = SpellLoader.build_spellbook([17_223])
      :ets.insert(PetTraining, {{:family_passives, 1}, family})

      on_exit(fn ->
        :ets.delete(PetTraining, {:family_passives, 1})
        :ets.insert(PetTraining, previous)
      end)

      progress = %PetProgress{
        level: 50,
        spells: [],
        loyalty: 2,
        training_points: 50,
        last_untrain_at: -123_456,
        last_untrain_cost: 5_000
      }

      owner = %Character{
        object: %Object{guid: Guid.from_low_guid(:player, 1)},
        unit: %Unit{level: 60, faction_template: 1},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}}
      }

      owner = owner |> Companion.suspend_as(:hunter_pet, 2960, 1515) |> Companion.capture_progress(progress)
      pet = Summon.build_pet(2960, owner)
      assert pet.internal.spellbook == family
      assert pet.internal.pet.family_spells == MapSet.new([17_223])
      assert PetProgression.snapshot(pet) == progress
      assert pet.unit.normal_resistance == trunc(3_018 * 1.05)
      assert Enum.map(pet.unit.auras, & &1.spell.id) == [17_223]
    end

    test "builds an owner-scaled demon from VMangos pet data" do
      owner_guid = Guid.from_low_guid(:player, 1)

      owner = %Character{
        object: %Object{guid: owner_guid},
        unit: %Unit{level: 50, faction_template: 1},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}}
      }

      pet = Summon.build_pet(416, owner)

      assert Guid.high_guid(pet.object.guid) == Guid.high_guid(:pet)
      assert pet.unit.level == 50
      assert pet.unit.health == 558
      assert pet.unit.max_power1 == 1450
      assert pet.unit.attack_power_model == :imp
      assert pet.unit.base_attack_power == pet.unit.base_strength - 10
      assert pet.unit.attack_power == pet.unit.strength - 10
      assert pet.unit.min_damage == pet.unit.base_min_damage
      assert pet.unit.max_damage == pet.unit.base_max_damage
      assert pet.unit.summoned_by == owner_guid
      assert (pet.unit.flags &&& 0x00000008) != 0
      assert pet.unit.faction_template == owner.unit.faction_template
      assert pet.internal.pet.owner_guid == owner_guid
      assert pet.internal.pet.profile == :combat
      assert pet.internal.running
      assert Enum.any?(pet.internal.creature.spells, &(&1.spell_id == 11_762))
      assert Map.has_key?(pet.internal.spellbook, 11_762)
      assert Map.has_key?(pet.internal.spellbook, 11_767)
    end

    test "loads every level-appropriate Succubus ability at its highest rank" do
      owner = %Character{
        object: %Object{guid: Guid.from_low_guid(:player, 1)},
        unit: %Unit{level: 50, faction_template: 1},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}}
      }

      pet = Summon.build_pet(1863, owner)

      assert Map.keys(pet.internal.spellbook) |> Enum.sort() == [6358, 7870, 11_778, 11_784]
      assert pet.unit.attack_power_model == :summoned_pet
      assert pet.unit.base_attack_power == pet.unit.base_strength * 2 - 20
      assert pet.unit.min_damage == pet.unit.base_min_damage
    end

    test "builds tameable beasts with generic hunter-pet stats and DBC family diet" do
      owner = %Character{
        object: %Object{guid: Guid.from_low_guid(:player, 1)},
        unit: %Unit{level: 50, faction_template: 1},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}}
      }

      pet = Summon.build_pet(69, owner)

      assert pet.internal.pet.kind == :hunter
      assert pet.internal.pet.food_mask == 1
      assert pet.unit.health == 2_215
      assert pet.unit.power_type == 2
      assert pet.unit.power3 == 100
      assert pet.unit.max_power5 == 1_050_000
      assert pet.unit.power5 == 166_500
    end

    test "keeps a freshly tamed beast's exact ranks and training debt at a higher owner level" do
      owner = %Character{
        object: %Object{guid: Guid.from_low_guid(:player, 1)},
        unit: %Unit{level: 50, faction_template: 1},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}}
      }

      pet = Summon.build_pet(2960, owner)
      {min_damage, max_damage} = Combat.damage_range(pet)

      assert_in_delta min_damage, 42.2625 * 0.75, 0.0001
      assert_in_delta max_damage, 53.2875 * 0.75, 0.0001
      assert Map.keys(pet.internal.spellbook) |> Enum.sort() == [17_255, 24_604]
      assert pet.internal.pet.training_points == -14
    end

    test "restores pet level XP and learned spells instead of scaling to the owner" do
      owner = %Character{
        object: %Object{guid: Guid.from_low_guid(:player, 1)},
        unit: %Unit{level: 60, faction_template: 1},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}}
      }

      owner =
        owner
        |> Companion.suspend_as(:hunter_pet, 2960, 1515)
        |> Companion.capture_progress(%PetProgress{
          level: 50,
          xp: 123,
          spells: [2649],
          loyalty: 4,
          loyalty_points: 12_345,
          training_points: 45
        })
        |> Companion.capture_reaction(:passive)
        |> Companion.capture_health(777)

      owner = put_in(owner.internal.companion.pet_number, 707)

      pet = Summon.build_pet(2960, owner)
      assert pet.unit.health == 777
      assert pet.unit.pet_number == 707
      assert Summon.with_health_percent(pet, nil).unit.health == 777
      assert Summon.with_health_percent(pet, 15).unit.health == 332
      assert Summon.build_pet(2960, Companion.capture_health(owner, 99_999)).unit.health == 2_215
      assert pet.unit.level == 50
      assert pet.unit.pet_experience == 123
      assert pet.unit.pet_next_level_exp == 36_875
      assert Map.keys(pet.internal.spellbook) == [2649]
      assert pet.internal.pet.reaction_state == :passive
      assert pet.unit.pet_loyalty == 4
      assert pet.internal.pet.loyalty_points == 12_345
      assert pet.internal.pet.training_points == 45
      assert pet.unit.training_points == -46
      assert pet.internal.pet.next_loyalty_at == nil
    end
  end
end
