defmodule ThistleTea.Game.Player.FishingMapsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Fishing
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader
  alias ThistleTea.Game.WorldRef

  @moduletag :namigator_maps
  @bobber_entry 35_591
  @shore {-9530.0, -240.0, 58.0, 0.0}
  @water {-9515.0, -240.0, 57.81, 0.0}

  setup [:caster, :bobber_template]

  describe "start_cast/2" do
    test "resolves launch requirements before attaching one interruptible bobber", ctx do
      state = start(ctx)
      character = state.character
      assert %Cast{phase: :channel_tick} = cast = character.internal.casting
      assert cast.channel_ms in [18_000, 22_000, 28_000, 32_000]
      assert character.unit.channel_spell == ctx.spell.id
      assert character.internal.channel_game_object_owned?
      guid = character.unit.channel_object
      assert guid == character.internal.channel_game_object_guid
      pid = Entity.pid(guid)
      assert is_pid(pid)
      on_exit(fn -> World.stop_entity(guid) end)
      refute_received %Effects.SummonGameObject{}
      assert_received {:"$gen_cast", {:send_packet, %Message.MsgChannelStart{spell_id: 900_855}}}

      moved = %{character | movement_block: %{character.movement_block | position: {-9529.0, -240.0, 58.0, 0.0}}}
      monitor = Process.monitor(pid)
      stopped = moved |> Casting.interrupt_movement(Time.now()) |> EventSink.emit_pending()
      assert stopped.internal.casting == nil
      assert stopped.internal.channel_game_object_guid == nil
      assert stopped.unit.channel_object == 0
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}
      assert Entity.pid(guid) == nil
      assert World.position(guid) == nil
    end

    test "does not create a bobber when launch requirements fail", ctx do
      spell = %{ctx.spell | attributes: MapSet.new([:channeled, :only_indoors])}
      state = start(%{ctx | spell: spell})
      assert state.character.internal.casting == nil
      assert state.character.internal.channel_game_object_guid == nil
      refute Map.has_key?(state, :fishing_position)
      refute_received %Effects.SummonGameObject{}
      refute_received {:"$gen_cast", {:send_packet, %Message.MsgChannelStart{}}}
    end
  end

  defp start(ctx) do
    character = Casting.start(ctx.caster, ctx.spell, Target.self(ctx.guid), Time.now())
    assert %Cast{phase: :preparing, requirements: :pending} = character.internal.casting
    Fishing.start_cast(%{guid: ctx.guid, character: character, fishing_position: @water}, ctx.spell)
  end

  defp caster(_context) do
    guid = System.unique_integer([:positive, :monotonic])
    {:ok, _} = Entity.register(guid)
    on_exit(fn -> Entity.unregister(guid) end)

    caster = %Character{
      object: %Object{guid: guid},
      player: %Player{},
      unit: %Unit{level: 10, health: 100, max_health: 100, power1: 100, max_power1: 100, auras: []},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: @shore, movement_flags: 0}
    }

    spell = %Spell{
      id: 900_855,
      cast_time_ms: 0,
      duration_ms: 30_000,
      interrupt_flags: 1,
      channel_interrupt_flags: 8,
      attributes: MapSet.new([:channeled, :only_outdoors]),
      effects: [
        %Effect{index: 0, type: :trans_door, misc_value: @bobber_entry, implicit_target_a: :caster_fishing_spot}
      ]
    }

    %{guid: guid, caster: caster, spell: spell}
  end

  defp bobber_template(_context) do
    previous = TemplateLoader.cached(@bobber_entry)
    TemplateLoader.put(%GameObjectTemplate{entry: @bobber_entry, type: 17, size: 1.0, flags: 0, faction: 0})

    on_exit(fn ->
      if previous, do: TemplateLoader.put(previous), else: :ets.delete(TemplateLoader, @bobber_entry)
    end)
  end
end
