defmodule ThistleTea.Game.World.Entity.EffectResolver.CapturedFollowerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest.CapturedFollower
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EffectResolver
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Test.Unique

  describe "resolve/2" do
    test "restores lost following without interrupting combat, evade or another player's request" do
      player = Unique.integer()
      creature = Unique.integer()
      character = %Character{object: %Object{guid: player}}
      request = %Effects.EnsureCapturedFollower{creature_guid: creature, player_guid: player}
      metadata = %{alive?: true, follow_guid: nil, in_combat: false, evading?: false}
      on_exit(fn -> Metadata.delete(creature) end)
      Metadata.put(creature, metadata)

      assert [%Effects.ForwardScriptSteps{target_guid: ^creature, source_guid: ^player, steps: [%{datalong: 15}]}] =
               EffectResolver.resolve(character, request)

      for unavailable <- [
            %{metadata | alive?: false},
            %{metadata | in_combat: true},
            %{metadata | evading?: true},
            %{metadata | follow_guid: player}
          ] do
        Metadata.put(creature, unavailable)
        assert EffectResolver.resolve(character, request) == []
      end

      Metadata.put(creature, metadata)
      assert EffectResolver.resolve(character, %{request | player_guid: Unique.integer()}) == []
      Metadata.delete(creature)
      assert EffectResolver.resolve(character, request) == []
    end
  end

  describe "emit/3" do
    test "a map change dismisses the captured creature in its original world" do
      player = Unique.integer()
      creature = Guid.from_low_guid(:mob, 10_990, Unique.integer())
      original_world = WorldRef.instance(30, Unique.integer())
      character = %Character{object: %Object{guid: player}, internal: %Internal{world: WorldRef.open(0)}}

      holder = %Holder{
        spell: %Spell{id: 21_863},
        caster_guid: creature,
        cast_context: %CastContext{caster_position: {original_world, 0.0, 0.0, 0.0}}
      }

      {:ok, _} = Entity.register(creature)
      on_exit(fn -> Entity.unregister(creature) end)
      [dismissal] = CapturedFollower.after_remove(character, holder, :source_unavailable)
      assert EventSink.emit(character, dismissal, Context.new(self())) == character
      assert_receive {:"$gen_cast", {:start_script, [%{command: :despawn, datalong: 1_000}], ^player, ^original_world}}
    end
  end
end
