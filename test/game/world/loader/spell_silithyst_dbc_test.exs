defmodule ThistleTea.Game.World.Loader.SpellSilithystDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Reputation
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "normalizes the capture reward's legacy reputation effect" do
      spell = SpellLoader.load(31_247)
      effect = Enum.find(spell.effects, &(&1.type == :reputation))
      assert effect.misc_value == 609

      assert {%Character{}, [%Effects.ReputationChange{faction_id: 609, value: 10}]} =
               Reputation.apply(%Character{}, %CastContext{}, spell, effect, 0)
    end

    test "loads carrier pickup, periodic refresh and faction movement limits" do
      assert Semantics.rules(SpellLoader.load(29_518)).dummy == :silithyst_pickup
      assert Semantics.rules(SpellLoader.load(30_176)).dummy == :silithyst_pvp
      carrier = SpellLoader.load(29_519)

      assert Enum.any?(
               carrier.effects,
               &match?(%{aura: :periodic_trigger_spell, trigger_spell_id: 30_176, amplitude_ms: 15_000}, &1)
             )

      for id <- [29_894, 29_895] do
        effect = Enum.find(SpellLoader.load(id).effects, &(&1.aura == :use_normal_movement_speed))
        assert Effect.roll(effect, 0) == 7
      end
    end
  end
end
