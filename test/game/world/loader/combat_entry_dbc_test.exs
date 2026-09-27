defmodule ThistleTea.Game.World.Loader.CombatEntryDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.CombatState
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  setup [:caster]

  describe "enter/2" do
    test "Blackfathom Channeling runs indefinitely until combat interrupts it", %{entity: entity} do
      spell = SpellLoader.load(8734)
      assert spell.duration_ms == -1
      entity = Casting.start(entity, spell, Target.self(1), 1_000)
      assert entity.internal.casting.phase == :channel_tick
      assert entity.unit.channel_spell == 8734
      assert Enum.any?(entity.internal.events, &match?(%Effects.ChannelStart{channel_time_ms: -1}, &1))
      assert {:waiting, entity, delay} = Casting.advance(entity, 61_000)
      assert delay > 0
      assert entity.unit.channel_spell == 8734
      entered = CombatState.enter(entity, 61_001)
      assert entered.internal.casting == nil
      assert entered.unit.channel_spell == 0
      assert Enum.any?(entered.internal.events, &match?(%Effects.ChannelUpdate{channel_time_ms: 0}, &1))
    end

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
    %{
      entity: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, auras: [], level: 50},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end
end
