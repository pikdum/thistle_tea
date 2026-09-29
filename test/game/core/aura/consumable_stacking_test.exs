defmodule ThistleTea.Game.Core.Aura.ConsumableStackingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.WorldRef

  setup [:character]

  describe "apply_spell/5" do
    test "new food replaces earlier recovery without cancelling a drink", %{character: character} do
      character = apply_spells(character, [food(1), drink(2), food(3)])
      assert ids(character) == [2, 3]
      assert Aura.flat_amount(character, :mod_regen) == 100
      assert Aura.flat_amount(character, :mod_power_regen) == 100
    end

    test "new drinks replace earlier drinks while retaining food", %{character: character} do
      character = apply_spells(character, [drink(1), food(2), drink(3)])
      assert ids(character) == [2, 3]
    end

    test "combined recovery replaces both separate recovery holders", %{character: character} do
      character = apply_spells(character, [food(1), drink(2), combined(3)])
      assert ids(character) == [3]
    end

    test "either separate recovery replaces the entire combined holder", %{character: character} do
      for replacement <- [food(2), drink(2)] do
        replaced = apply_spells(character, [combined(1), replacement])
        assert ids(replaced) == [2]

        refute Aura.has_aura?(
                 replaced,
                 if(replacement.exclusive_category == :food, do: :mod_power_regen, else: :mod_regen)
               )
      end
    end

    test "Well Fed replaces across sources and recomputes the bonus once", %{character: character} do
      first = stat_buff(1, :well_fed, 10)
      second = stat_buff(2, :well_fed, 20)
      {character, _events} = Aura.apply_spell(character, 1, 60, first, 1000)
      assert character.unit.strength == 20
      {character, _events} = Aura.apply_spell(character, 2, 60, second, 2000)
      assert ids(character) == [2]
      assert character.unit.strength == 30
      {character, _events} = Aura.expire_due(character, 32_000)
      assert character.unit.strength == 10
    end

    test "standing ends recovery while the lasting food bonus remains", %{character: character} do
      character = apply_spells(character, [combined(1), stat_buff(2, :well_fed, 10)])
      {character, _events} = Aura.remove_with_interrupt_flags(character, Aura.interrupt_mask(:stand), 2000)
      assert ids(character) == [2]
      assert character.unit.strength == 20
    end

    test "replaced food cannot later trigger its Well Fed buff", %{character: character} do
      trigger = %Effect{
        index: 1,
        type: :apply_aura,
        aura: :periodic_trigger_spell,
        trigger_spell_id: 19_705,
        amplitude_ms: 10_000
      }

      old = food(1)
      old = %{old | effects: old.effects ++ [trigger]}
      character = apply_spells(character, [old, food(2)])
      {character, events} = Aura.tick(character, 11_000)
      assert ids(character) == [2]
      refute Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 19_705}, &1))
    end

    test "flasks replace one another but preserve ordinary elixirs and Well Fed", %{character: character} do
      character = apply_spells(character, [stat_buff(1, :flask, 10), stat_buff(2, nil, 5), stat_buff(3, :well_fed, 2)])
      character = apply_spells(character, [stat_buff(4, :flask, 20), stat_buff(5, nil, 3)])
      assert ids(character) == [2, 3, 4, 5]
      assert character.unit.strength == 40
    end

    test "death retains the replacement flask without restoring the removed flask", %{character: character} do
      flask = stat_buff(2, :flask, 20)
      flask = %{flask | attributes: MapSet.new([:death_persistent])}
      character = apply_spells(character, [stat_buff(1, :flask, 10), flask, stat_buff(3, :well_fed, 2)])
      character = Entity.take_damage(character, 100, 2000)
      assert ids(character) == [2]
      assert character.unit.strength == 30
    end
  end

  defp apply_spells(character, spells) do
    Enum.reduce(spells, character, fn spell, entity -> elem(Aura.apply_spell(entity, 1, 60, spell, 1000), 0) end)
  end

  defp ids(character), do: character.unit.auras |> Enum.map(& &1.spell.id) |> Enum.sort()

  defp food(id), do: recovery(id, :food, [:mod_regen])
  defp drink(id), do: recovery(id, :drink, [:mod_power_regen])
  defp combined(id), do: recovery(id, :food_and_drink, [:mod_regen, :mod_power_regen])

  defp recovery(id, category, types) do
    effects =
      Enum.with_index(types, fn type, index ->
        %Effect{index: index, type: :apply_aura, aura: type, base_points: 100, misc_value: 0}
      end)

    %Spell{id: id, exclusive_category: category, duration_ms: 30_000, aura_interrupt_flags: 0x40000, effects: effects}
  end

  defp stat_buff(id, category, amount) do
    %Spell{
      id: id,
      exclusive_category: category,
      duration_ms: 30_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stat, base_points: amount, misc_value: 0}]
    }
  end

  defp character(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 1000, base_strength: 10, strength: 10, level: 60, auras: []},
      player: %Player{},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{character: character}
  end
end
