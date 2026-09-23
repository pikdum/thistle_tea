defmodule ThistleTea.Game.World.Loader.TotemTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.World.Loader.Summon
  alias ThistleTea.Game.World.Loader.Totem
  alias ThistleTea.Game.WorldRef

  @moduletag :namigator_maps

  describe "build/3" do
    test "anchors template stamina before applying spell-defined health" do
      entry = 987_654
      previous = :ets.lookup(Summon, entry)

      seed = %Mangos.Creature{
        id: entry,
        modelid: 3,
        creature_movement: [],
        equip_items: [nil, nil, nil],
        creature_template: %Mangos.CreatureTemplate{
          entry: entry,
          name: "Test Standard",
          scale: 1.0,
          min_level: 1,
          max_level: 1,
          health_multiplier: 1.0,
          mana_multiplier: 1.0
        },
        creature_class_level_stats: %Mangos.CreatureClassLevelStats{
          class: 1,
          level: 1,
          health: 42,
          mana: 0,
          melee_damage: 0.0,
          ranged_damage: 0.0,
          stamina: 22
        }
      }

      :ets.insert(Summon, {entry, seed})

      on_exit(fn ->
        :ets.delete(Summon, entry)
        :ets.insert(Summon, previous)
      end)

      owner = %Character{
        object: %Object{guid: 1},
        unit: %Unit{level: 50, faction_template: 1},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {-8949.0, -132.0, 83.5, 0.0}}
      }

      effect = %{Effects.summon_totem(entry, nil, 120_000) | health: 1500}
      ward = Totem.build(owner, effect, 1000)
      assert ward.unit.base_stamina == 22
      assert ward.unit.health == 1500
      assert ward.unit.max_health == 1500
      assert Stats.recompute(ward.unit).max_health == 1500
    end
  end
end
