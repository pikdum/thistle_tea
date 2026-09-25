defmodule ThistleTea.Game.Entity.Logic.Aura.HealthSyncTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:character]

  describe "sync/2" do
    test "ordinary maximum-health buffs do not heal", %{character: character} do
      {buffed, _} = cast(character, health_spell(1, 100), 1000)
      assert buffed.unit.max_health == 1100
      assert buffed.unit.health == 500
      {normal, _} = Aura.remove_spells(buffed, [1], 2000)
      assert normal.unit.health == 500
    end

    test "temporary health is removed without killing an injured player", %{character: character} do
      {buffed, _} = cast(character, health_spell(12_976, 0), 1000)
      assert buffed.unit.max_health == 1300
      assert buffed.unit.health == 800
      injured = %{buffed | unit: %{buffed.unit | health: 100}}
      {normal, _} = Aura.remove_spells(injured, [12_976], 2000)
      assert normal.unit.health == 1
      assert normal.unit.max_health == 1000
    end

    test "repeated Bear transformations preserve partial health", %{character: character} do
      bear = %{
        health_spell(5487, 400)
        | effects: [
            %Effect{type: :apply_aura, aura: :mod_shapeshift, misc_value: 5} | health_spell(5487, 400).effects
          ]
      }

      Enum.reduce(1..10, character, fn index, current ->
        {shifted, _} = cast(current, bear, index * 2000)
        assert shifted.unit.max_health == 1400
        assert shifted.unit.health == 700
        {normal, _} = Aura.cancel_spell(shifted, 5487, index * 2000 + 1000)
        assert normal.unit.health == 500
        assert normal.unit.max_health == 1000
        normal
      end)
    end

    test "dead players stay dead when temporary or proportional health ends", %{character: character} do
      {buffed, _} = cast(character, health_spell(12_976, 0), 1000)
      dead = %{buffed | unit: %{buffed.unit | health: 0}}
      {normal, _} = Aura.remove_spells(dead, [12_976], 2000)
      assert normal.unit.health == 0
    end
  end

  defp character(_context) do
    unit = Stats.recompute(%Unit{class: 11, level: 60, base_health: 1000, health: 500, auras: []})

    %{
      character: %Character{
        object: %Object{guid: 1},
        unit: unit,
        player: %Player{},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp health_spell(id, amount),
    do: %Spell{id: id, effects: [%Effect{type: :apply_aura, aura: :mod_increase_health, base_points: amount}]}

  defp cast(character, spell, now), do: Aura.apply_spell(character, 1, 60, spell, now)
end
