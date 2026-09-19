defmodule ThistleTea.Game.Entity.Logic.PeriodicDeathTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:entity]

  describe "tick/2" do
    test "advances every retained resource aura without affecting corpses", %{entity: entity} do
      types = [
        :periodic_damage,
        :periodic_damage_percent,
        :periodic_leech,
        :periodic_mana_leech,
        :periodic_power_burn,
        :periodic_heal,
        :obs_mod_health,
        :obs_mod_mana,
        :periodic_energize
      ]

      entity =
        types
        |> Enum.with_index(1)
        |> Enum.reduce(entity, fn {type, id}, entity ->
          {entity, _events} = Aura.apply_spell(entity, 2, 60, persistent_spell(id, [type]), 0)
          entity
        end)

      entity = Core.take_damage(entity, 1_000, 500)
      {entity, events} = Aura.tick(entity, 1_000)
      assert entity.unit.health == 0
      assert entity.unit.power1 == 100
      assert events == []
      assert length(entity.unit.auras) == length(types)
      assert Aura.next_event_at(entity) == 2_000
      assert Enum.all?(entity.unit.auras, &(hd(&1.auras).next_tick_at == 2_000))
      {entity, _events} = Aura.tick(entity, 3_000)
      assert entity.unit.auras == []
      assert Aura.next_event_at(entity) == nil
    end

    test "lethal damage cannot be undone by a later effect in the same tick", %{entity: entity} do
      spell = %{persistent_spell(1, [:periodic_damage, :periodic_heal, :obs_mod_mana]) | attributes: MapSet.new()}
      {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
      {entity, events} = Aura.tick(entity, 1_000)
      assert entity.unit.health == 0
      assert entity.unit.power1 == 100
      assert entity.unit.auras == []
      assert Aura.next_event_at(entity) == nil
      assert Enum.any?(events, &match?(%Effects.SpellDamage{}, &1))
      refute Enum.any?(events, &match?(%Effects.SpellHeal{}, &1))
      refute Enum.any?(events, &match?(%Effects.PeriodicAuraLog{}, &1))
    end
  end

  defp entity(_context) do
    %{
      entity: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 50, max_health: 1_000, power1: 100, max_power1: 1_000, level: 60, auras: []},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp persistent_spell(id, types) do
    effects =
      types
      |> Enum.with_index()
      |> Enum.map(fn {type, index} ->
        %Effect{index: index, type: :apply_aura, aura: type, base_points: 100, amplitude_ms: 1_000}
      end)

    %Spell{id: id, duration_ms: 3_000, attributes: MapSet.new([:passive]), effects: effects}
  end
end
