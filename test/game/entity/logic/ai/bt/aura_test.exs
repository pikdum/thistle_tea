defmodule ThistleTea.Game.Entity.Logic.AI.BT.AuraTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Aura, as: AuraBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  describe "tick/3" do
    test "queues periodic aura events on the entity" do
      now = 1_000
      entity = fixture_entity()
      spell = dot_spell()
      {entity, _events} = Aura.apply_spell(entity, 999, 1, spell, now)

      entity =
        update_in(entity.unit.auras, fn [holder] ->
          [
            update_in(holder.auras, fn [aura] ->
              [%{aura | next_tick_at: now - 1}]
            end)
          ]
        end)

      assert {:failure, entity, %Blackboard{}} = AuraBT.tick(entity, Blackboard.new(), now)

      assert entity.unit.health == 50

      assert [
               %{
                 type: :spell_damage,
                 source_guid: 999,
                 target_guid: 1,
                 spell_id: 11_366,
                 damage: 50,
                 periodic?: true
               }
             ] = entity.internal.events
    end

    test "leaves entities without auras unchanged" do
      entity = fixture_entity()

      assert {:failure, ^entity, %Blackboard{}} = AuraBT.tick(entity, Blackboard.new(), 1_000)
    end
  end

  defp fixture_entity do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{level: 1, health: 100, max_health: 100, auras: []},
      internal: %Internal{map: 0}
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
