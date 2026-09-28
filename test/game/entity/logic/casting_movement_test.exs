defmodule ThistleTea.Game.Entity.Logic.CastingMovementTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.BoundaryResult
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:caster]

  describe "advance/2" do
    test "accumulates displacement and cancels before costs or launch", ctx do
      started = Casting.start(ctx.caster, ctx.spell, ctx.target, 1_000)
      assert {:waiting, small, _} = started |> move({0.3, 0.0, 0.0, 0.0}) |> Casting.advance(1_100)
      assert {:waiting, edge, _} = small |> move({0.5, 0.0, 0.0, 0.0}) |> Casting.advance(1_200)
      assert {:finished, stopped} = edge |> move({0.6, 0.0, 0.0, 0.0}) |> Casting.advance(2_000)
      assert stopped.internal.casting == nil
      assert stopped.internal.cooldowns == %{}
      assert stopped.unit.power1 == 100
      assert stopped.unit.health == 50
      refute Enum.any?(stopped.internal.events, &is_struct(&1, Effects.SpellGo))
      EventSink.emit_pending(stopped, Context.new(self()))
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{spell: 900_853, reason: 0x2E}}}
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgSpellFailure{spell: 900_853, result: 0x2E}}}
    end

    test "moving casts without the interrupt flag complete normally", ctx do
      completed =
        ctx.caster
        |> Casting.start(%{ctx.spell | interrupt_flags: 0}, ctx.target, 1_000)
        |> move({2.0, 0.0, 0.0, 1.0})
        |> Casting.complete(2_000)

      assert completed.internal.casting == nil
      assert completed.unit.power1 == 70
      assert completed.unit.health > 50
      assert Enum.any?(completed.internal.events, &is_struct(&1, Effects.SpellGo))
    end

    test "reanchors movement when preparation becomes a channel", ctx do
      channel = %{ctx.spell | attributes: MapSet.new([:channeled]), duration_ms: 5_000, channel_interrupt_flags: 8}

      started =
        ctx.caster
        |> Casting.start(channel, ctx.target, 1_000)
        |> move({0.4, 0.0, 0.0, 0.0})
        |> Casting.complete(2_000)

      assert %Cast{phase: :channel_tick} = started.internal.casting
      assert started.internal.casting.movement_origin.position == {0.4, 0.0, 0.0, 0.0}
      assert {:waiting, kept, _} = started |> move({0.8, 0.0, 0.0, 0.0}) |> Casting.advance(2_100)
      assert {:finished, stopped} = kept |> move({1.0, 0.0, 0.0, 0.0}) |> Casting.advance(2_200)
      assert stopped.unit.channel_spell == 0
      assert stopped.unit.channel_object == 0
    end

    test "turning cancels channel auras and their future ticks", ctx do
      channel = %{
        ctx.spell
        | cast_time_ms: 0,
          attributes: MapSet.new([:channeled]),
          duration_ms: 10_000,
          channel_interrupt_flags: 0x10,
          effects: [
            %Effect{
              index: 0,
              type: :apply_aura,
              aura: :obs_mod_health,
              base_points: 7,
              amplitude_ms: 2_000,
              implicit_target_a: :caster
            }
          ]
      }

      started = Casting.start(ctx.caster, channel, ctx.target, 1_000)
      assert Aura.has_spell?(started, channel.id)
      assert {:finished, stopped} = started |> move({0.0, 0.0, 0.0, 0.1}) |> Casting.advance(1_100)
      refute Aura.has_spell?(stopped, channel.id)
      assert stopped.unit.channel_object == 0
      assert stopped.unit.channel_spell == 0
      assert Enum.count(stopped.internal.events, &match?(%Effects.ChannelUpdate{channel_time_ms: 0}, &1)) == 1
      assert Enum.any?(stopped.internal.events, &match?(%Effects.DespawnAreaEffects{spell_id: 900_853}, &1))
      {later, _events} = Aura.tick(stopped, 20_000)
      assert later.unit.health == stopped.unit.health
    end
  end

  describe "interrupt_movement/2" do
    test "releases owned channel objects once while successful completion retains them", ctx do
      started =
        ctx.caster
        |> Casting.start_game_object_channel(777, %{ctx.spell | channel_interrupt_flags: 0x10}, 30_000, 1_000)
        |> BoundaryResult.apply(%Commands.ChannelGameObjectStarted{guid: 777})

      stopped = started |> move({0.0, 0.0, 0.0, 0.1}) |> Casting.interrupt_movement(1_100)
      assert stopped.internal.channel_game_object_guid == nil
      assert stopped.internal.channel_game_object_owned? == nil
      assert stopped.internal.casting == nil
      assert Enum.count(stopped.internal.events, &match?(%Effects.DespawnEntity{target_guid: 777}, &1)) == 1
      assert Casting.interrupt_movement(stopped, 1_200) == stopped

      finished = Casting.finish_game_object_channel(started, 777)
      assert finished.internal.casting == nil
      assert finished.internal.channel_game_object_guid == nil
      refute Enum.any?(finished.internal.events, &is_struct(&1, Effects.DespawnEntity))
    end
  end

  defp move(caster, position), do: %{caster | movement_block: %{caster.movement_block | position: position}}

  defp caster(_context) do
    %{
      caster: %Character{
        object: %Object{guid: 91_985_310},
        unit: %Unit{level: 10, health: 50, max_health: 100, power1: 100, max_power1: 100, auras: []},
        player: %Player{},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{movement_flags: 0, position: {0.0, 0.0, 0.0, 0.0}}
      },
      spell: %Spell{
        id: 900_853,
        school: :holy,
        mana_cost: 30,
        power_type: 0,
        cast_time_ms: 1_000,
        interrupt_flags: 1,
        gcd_ms: 1_500,
        gcd_category: 133,
        recovery_time_ms: 5_000,
        effects: [%Effect{index: 0, type: :heal, implicit_target_a: :caster, base_points: 9}]
      },
      target: Target.self(91_985_310)
    }
  end
end
