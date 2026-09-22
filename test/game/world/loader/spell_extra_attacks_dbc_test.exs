defmodule ThistleTea.Game.World.Loader.SpellExtraAttacksDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "loads vanilla extra attack counts from effect 19" do
      for {id, count} <- [{3391, 2}, {15_601, 1}, {15_642, 3}, {16_459, 1}, {8233, 2}, {20_178, 1}] do
        spell = SpellLoader.load(id)
        effect = Enum.find(spell.effects, &(&1.type == :add_extra_attacks))
        assert %Effect{} = effect
        assert Effect.roll(effect, 0) == count
      end
    end
  end

  describe "resolve/2" do
    test "rejects recursive extra-attack triggers before any part of a mixed spell applies" do
      entity = %Character{
        object: %Object{guid: 1},
        player: %Player{},
        unit: %Unit{level: 60, health: 100, max_health: 100},
        internal: %Internal{}
      }

      for id <- [3391, 15_601, 15_642, 16_459, 8233, 20_178] do
        recursive = Effects.trigger_spell(1, 60, 1, id, extra_attack?: true)
        assert Spells.resolve(entity, recursive) == []
        resolved = Spells.resolve(entity, %{recursive | extra_attack?: false})
        assert Enum.any?(resolved, &match?(%Effects.DeliverSpell{cast_context: %{extra_attack?: false}}, &1))
      end
    end
  end
end
