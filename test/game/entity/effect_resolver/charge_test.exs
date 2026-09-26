defmodule ThistleTea.Game.Entity.EffectResolver.ChargeTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.BoundaryResult
  alias ThistleTea.Game.Entity.Logic.Charge
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.SmsgMonsterMove
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @moduletag :namigator_maps

  setup [:entities]

  describe "resolve/2" do
    test "triggered player and creature spells charge from the caster before delivering effects", context do
      for caster <- [context.character, context.mob] do
        trigger = Effects.trigger_spell(caster.object.guid, 60, context.target.object.guid, context.spell.id)
        events = EffectResolver.resolve(caster, trigger)

        assert [
                 %Effects.SpellGo{},
                 %Effects.ChargeResolved{} = movement,
                 %Effects.DeliverSpell{},
                 %Effects.SpellCastCompleted{}
               ] = events

        assert movement.duration_ms > 0
        assert movement.duration_ms < 2_000
        assert {x, y, _z, _o} = movement.destination
        assert_in_delta x, -8965.45, 0.1
        assert_in_delta y, -132.49, 0.1
        assert_in_delta movement.duration_ms, 646, 2
        assert movement.attack_target.guid == context.target.object.guid
        assert movement.swing_delay_ms == 968
        assert [%Effects.TriggerSpellRequest{source_guid: source}] = EffectResolver.resolve(context.target, trigger)
        assert source == caster.object.guid
      end
    end

    test "nonattacking charges still carry the swing delay without an arrival attack", context do
      [movement] = EffectResolver.resolve(context.character, Effects.charge(context.target.object.guid))
      assert movement.attack_target == nil
      assert movement.swing_delay_ms == 968
    end

    test "charges reject dead, rooted and taxi casters and targets in another world", context do
      %{character: caster, target: target} = context
      request = Effects.charge(target.object.guid)

      for invalid <- [
            %{caster | unit: %{caster.unit | health: 0}},
            %{caster | movement_block: %{caster.movement_block | movement_flags: 0x08000000}},
            %{caster | internal: %{caster.internal | taxi_flight: %{}}},
            %{caster | internal: %{caster.internal | world: WorldRef.instance(0, 777)}}
          ] do
        assert EffectResolver.resolve(invalid, request) == []
      end

      assert EffectResolver.resolve(caster, Effects.charge(caster.object.guid)) == []
      assert EffectResolver.resolve(caster, Effects.charge(999_999_999)) == []
    end
  end

  describe "emit/3" do
    test "both owners receive the same movement and spline id broadcast to observers", context do
      observer = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      Entity.register(observer)
      SpatialHash.update(:players, observer, context.character.internal.world, -8949.95, -132.49, 83.29)

      on_exit(fn ->
        Entity.unregister(observer)
        SpatialHash.remove(:players, observer)
      end)

      for caster <- [context.character, context.mob] do
        [effect] = EffectResolver.resolve(caster, Effects.charge(context.target.object.guid))
        assert EventSink.emit(caster, effect, Context.new(self())) == caster
        assert_receive %Commands.ChargePathResolved{} = command
        moved = BoundaryResult.apply(caster, command)
        assert Charge.active?(moved, command.started_at)
        EventSink.emit_pending(moved, Context.new(self()))
        assert_receive {:"$gen_cast", {:send_packet, %SmsgMonsterMove{} = packet, opts}}
        assert opts[:source_guid] == caster.object.guid
        assert packet.spline_id == moved.internal.spline_id
        assert packet.splines == moved.movement_block.spline_nodes
        assert packet.duration == moved.movement_block.duration
        assert is_binary(SmsgMonsterMove.to_binary(packet))
        arrived = Charge.reconcile(moved, command.started_at + command.duration_ms)
        assert arrived.internal.charge == nil
        assert arrived.movement_block.spline_nodes == []
      end
    end
  end

  defp entities(_context) do
    spell = %Spell{id: 99_777_555, effects: [%Effect{index: 0, type: :charge, implicit_target_a: :target_enemy}]}
    internal = %Internal{world: WorldRef.open(0), spline_id: 1, spellbook: %{spell.id => spell}, running: true}
    unit = %Unit{health: 100, max_health: 100, level: 60, auras: []}

    movement = %MovementBlock{
      position: {-8949.95, -132.49, 83.29, 0.0},
      movement_flags: 0,
      run_speed: 7.0,
      walk_speed: 2.5
    }

    character = %Character{
      object: %Object{guid: Guid.from_low_guid(:player, System.unique_integer([:positive]))},
      unit: unit,
      player: %Player{},
      internal: internal,
      movement_block: movement
    }

    mob = %Mob{object: %Object{guid: Guid.runtime(:mob, 1)}, unit: unit, internal: internal, movement_block: movement}

    target = %{
      mob
      | object: %Object{guid: Guid.runtime(:mob, 1)},
        movement_block: %{movement | position: {-8969.95, -132.49, 83.29, 0.0}}
    }

    World.update_position(target)
    Metadata.put(target.object.guid, %{alive?: true, level: 60, no_spell_defense?: true})

    on_exit(fn ->
      World.remove_position(target)
      Metadata.delete(target.object.guid)
    end)

    %{character: character, mob: mob, target: target, spell: spell}
  end
end
