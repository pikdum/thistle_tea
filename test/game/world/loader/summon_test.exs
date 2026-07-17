defmodule ThistleTea.Game.World.Loader.SummonTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.Summon
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  describe "build_pet/2" do
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
      assert pet.unit.summoned_by == owner_guid
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
      assert pet.internal.pet.food_mask == 208
      assert pet.unit.health == 2_215
      assert pet.unit.power_type == 2
      assert pet.unit.power3 == 100
      assert pet.unit.max_power5 == 1_050_000
      assert pet.unit.power5 == 166_500
    end
  end
end
