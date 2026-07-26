defmodule ThistleTea.Game.Entity.Logic.AI.BehaviorRunnerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  describe "tick/3" do
    test "runs aura and regeneration upkeep outside the behavior tree" do
      now = 1_000
      entity = fixture()
      {entity, _events} = Aura.apply_spell(entity, 999, 1, dot_spell(), now)

      entity =
        update_in(entity.unit.auras, fn [holder] ->
          [
            update_in(holder.auras, fn [aura] ->
              [%{aura | next_tick_at: now - 1}]
            end)
          ]
        end)

      tree = BT.action(fn entity, blackboard -> {:failure, entity, blackboard} end)

      assert {:failure, entity} = BehaviorRunner.tick(tree, entity, Context.new(now))
      assert entity.unit.health == 83

      assert [%Effects.SpellDamage{spell_id: 11_366, periodic?: true}] = entity.internal.events
    end
  end

  defp fixture do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{level: 1, health: 100, max_health: 100, auras: []},
      internal: %Internal{world: %WorldRef{map_id: 0}}
    }
  end

  defp dot_spell do
    %Spell{
      id: 11_366,
      name: "Pyroblast",
      school: :fire,
      duration_ms: 12_000,
      effects: [
        %Effect{
          index: 1,
          type: :apply_aura,
          base_points: 50,
          die_sides: 0,
          aura: :periodic_damage,
          amplitude_ms: 3_000
        }
      ]
    }
  end
end
