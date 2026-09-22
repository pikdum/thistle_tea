defmodule ThistleTea.Game.World.Loader.SpellDurabilityDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "preserves signed repair amounts and exact equipment slots" do
      for {id, mode, amount, scope} <- [
            {21_388, :points, 1, {:slot, 15}},
            {22_619, :points, 1, {:slot, 16}},
            {23_437, :percent, 100, {:slot, 17}},
            {23_438, :points, -50_000, {:slot, 17}}
          ] do
        spell = SpellLoader.load(id)
        target = character()
        context = %CastContext{caster_guid: if(id == 21_388, do: 2, else: 1), caster_level: 60}
        {^target, [%Effects.DurabilityLoss{} = effect]} = SpellEffect.receive(target, context, spell, 1000)
        assert {effect.mode, effect.amount, effect.scope} == {mode, amount, scope}
        assert effect.spell_id == id
        assert effect.target_guid == 1
      end
    end

    test "the multi-effect test spell decodes negative all-item selectors" do
      spell = SpellLoader.load(16_722)
      target = character()
      context = %CastContext{caster_guid: 1, caster_level: 60}
      {^target, effects} = SpellEffect.receive(target, context, spell, 1000)

      assert Enum.map(effects, &{&1.mode, &1.amount, &1.scope}) == [
               {:points, 5, :carried},
               {:percent, 50, {:slot, 15}},
               {:points, 1, :equipped}
             ]
    end
  end

  defp character do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100},
      player: %Player{},
      internal: %Internal{}
    }
  end
end
