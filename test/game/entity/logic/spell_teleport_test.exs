defmodule ThistleTea.Game.Entity.Logic.SpellTeleportTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EffectResolver
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.WorldRef

  setup [:entities]

  describe "receive/4" do
    test "retains forward distance and projects explicit destinations to the owner", data do
      assert {_, [%Effects.TeleportNearCaster{destination: {:forward, 5.0}}]} =
               SpellEffect.receive(data.target, data.context, data.spell, 1000)

      context = %{data.context | destination_position: {20.0, 30.0, 40.0}}
      assert {target, [request]} = SpellEffect.receive(data.target, context, data.spell, 1000)

      assert [%Effects.TeleportToWorld{position: {20.0, 30.0, 40.0}, preserve_combat?: true} = effect] =
               EffectResolver.resolve(target, request)

      assert_in_delta effect.orientation, 2 * :math.pi() - 1.0, 0.0001
      assert ^target = EventSink.emit(target, effect, Context.new(self()))
      world = target.internal.world
      assert_receive {:"$gen_cast", {:combat_teleport, 20.0, 30.0, 40.0, orientation, ^world}}
      assert orientation == effect.orientation
    end

    test "uses the caster origin for caster-destination selectors", data do
      spell = %{data.spell | effects: [%{hd(data.spell.effects) | implicit_target_b: :caster_destination}]}

      assert {_, [%Effects.TeleportNearCaster{destination: {:position, {1.0, 2.0, 3.0}}}]} =
               SpellEffect.receive(data.target, data.context, spell, 1000)
    end

    test "rejects taxi passengers and targets in another world copy", data do
      for internal <- [
            %{data.target.internal | taxi_flight: %{}},
            %{data.target.internal | world: WorldRef.instance(529, 2)}
          ] do
        target = %{data.target | internal: internal}
        assert {^target, []} = SpellEffect.receive(target, data.context, data.spell, 1000)
      end

      {_, [request]} = SpellEffect.receive(data.target, data.context, data.spell, 1000)
      changed = %{data.target | internal: %{data.target.internal | world: WorldRef.instance(529, 2)}}
      assert EffectResolver.resolve(changed, request) == []
    end

    test "resolves database coordinates within the current instance", data do
      key = {:target_position, data.spell.id}
      previous = :ets.lookup(SpellLoader, key)
      :ets.insert(SpellLoader, {key, %{map: 529, x: 7.0, y: 8.0, z: 9.0}})

      on_exit(fn ->
        :ets.delete(SpellLoader, key)
        :ets.insert(SpellLoader, previous)
      end)

      spell = %{data.spell | effects: [%{hd(data.spell.effects) | implicit_target_b: 17}]}
      assert {_, [request]} = SpellEffect.receive(data.target, data.context, spell, 1000)

      assert [%Effects.TeleportToWorld{world: world, position: {7.0, 8.0, 9.0}}] =
               EffectResolver.resolve(data.target, request)

      assert world == data.target.internal.world
    end
  end

  defp entities(_context) do
    world = WorldRef.instance(529, 1)

    target = %Character{
      object: %Object{guid: 2},
      unit: %Unit{health: 100, max_health: 100, level: 50, bounding_radius: 0.5},
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {50.0, 20.0, 3.0, 0.0}}
    }

    context = %CastContext{
      caster_guid: 1,
      caster_level: 50,
      caster_position: {world, 1.0, 2.0, 3.0},
      caster_orientation: 1.0,
      caster_bounding_radius: 1.0,
      target_role: :other,
      hit_outcome: :hit
    }

    spell = %Spell{
      id: 15_734,
      effects: [
        %Effect{
          type: :teleport_units_face_caster,
          implicit_target_a: :target_enemy,
          implicit_target_b: 47,
          radius_yards: 5.0
        }
      ]
    }

    %{target: target, context: context, spell: spell}
  end
end
