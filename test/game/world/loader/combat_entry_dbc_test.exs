defmodule ThistleTea.Game.World.Loader.CombatEntryDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.CombatState
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  setup [:caster]

  describe "enter/2" do
    test "mounts and resurrection stop while combat-usable casts continue", %{entity: entity} do
      for {id, interrupted?} <- [{458, true}, {2006, true}, {133, false}, {587, false}, {688, false}, {8690, false}] do
        spell = SpellLoader.load(id)
        assert Spell.attribute?(spell, :not_in_combat) == interrupted?
        assert spell.cast_time_ms > 0
        casting = %{entity | internal: %{entity.internal | casting: Cast.new(spell, Target.self(1), 1_000)}}
        entered = CombatState.enter(casting, 1_500)
        assert is_nil(entered.internal.casting) == interrupted?
      end
    end

    test "Destroy Spear stops and clears its channel", %{entity: entity} do
      spell = SpellLoader.load(16_557)
      assert Spell.attribute?(spell, :channeled)
      cast = %{Cast.new(spell, Target.self(1), 1_000) | phase: :channel_tick}
      entity = %{entity | internal: %{entity.internal | casting: cast}, unit: %{entity.unit | channel_spell: spell.id}}
      entered = CombatState.enter(entity, 1_500)
      assert entered.internal.casting == nil
      assert entered.unit.channel_spell == 0
      assert Enum.any?(entered.internal.events, &match?(%Effects.ChannelUpdate{channel_time_ms: 0}, &1))
    end
  end

  defp caster(_context) do
    %{entity: %Mob{object: %Object{guid: 1}, unit: %Unit{health: 100, auras: []}, internal: %Internal{}}}
  end
end
