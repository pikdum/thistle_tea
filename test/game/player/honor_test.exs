defmodule ThistleTea.Game.Player.HonorTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Honor, as: HonorData
  alias ThistleTea.Game.Entity.Data.Honor.Award
  alias ThistleTea.Game.Entity.Data.Honor.Damage
  alias ThistleTea.Game.Entity.Data.Honor.Snapshot
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Player.Honor
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.System.Honor, as: HonorSystem
  alias ThistleTea.Game.WorldRef

  describe "combat credit" do
    test "receives multiple hits in one effect drain and restores totals on reconnect" do
      killer = character(1) |> Honor.sync()
      victim = character(2) |> Honor.sync()
      Presence.enter(killer, %{race: 1, alive?: true})
      on_exit(fn -> Presence.leave(killer) end)

      victim =
        victim
        |> Core.take_damage(40, 1000, source: killer.object.guid)
        |> Core.take_damage(100, 1100, source: killer.object.guid)

      {victim, effects} = Effects.drain(victim)
      effects = Enum.filter(effects, &match?(%Effects.HonorDamage{}, &1))
      victim = EventSink.emit(victim, effects)
      assert victim.internal.honor_damage == %Damage{}
      assert HonorSystem.snapshot(killer.object.guid).honor.lifetime_honorable_kills == 1

      reconnected = Honor.sync(killer)
      assert reconnected.player.session_kills == 1
      assert reconnected.player.this_week_contribution == 188
      assert reconnected.player.lifetime_honorable_kills == 1
      assert CharacterStore.get(killer.id).player == reconnected.player
      assert reconnected.player.coinage == 123
    end
  end

  describe "inspect_reply/3" do
    test "rejects distant, hostile, offline, and other-instance targets" do
      character = character(1)
      world = character.internal.world
      snapshot = %Snapshot{honor: %HonorData{}, day: 5, week_start: 5}

      opts = [
        online?: fn _guid -> true end,
        position: fn _guid -> {world, 10.0, 0.0, 0.0} end,
        attackable?: fn _character, _guid -> false end,
        snapshot: fn _guid -> snapshot end
      ]

      assert %Message.MsgInspectHonorStats{guid: 2} = Honor.inspect_reply(character, 2, opts)
      assert Honor.inspect_reply(character, 2, Keyword.put(opts, :online?, fn _guid -> false end)) == nil
      assert Honor.inspect_reply(character, 2, Keyword.put(opts, :attackable?, fn _character, _guid -> true end)) == nil

      for position <- [{world, 10.01, 0.0, 0.0}, {WorldRef.instance(0, 1), 0.0, 0.0, 0.0}, nil] do
        assert Honor.inspect_reply(character, 2, Keyword.put(opts, :position, fn _guid -> position end)) == nil
      end
    end
  end

  describe "honor messages" do
    test "dispatches inspection and encodes the build-5875 response" do
      packet = %Packet{opcode: Opcodes.get(:MSG_INSPECT_HONOR_STATS), payload: <<7::little-size(64)>>}
      assert %Message.CmsgInspectHonorStats{guid: 7} = Dispatch.to_message(packet)

      player = %Player{
        highest_honor_rank: 9,
        session_kills: 0x00020003,
        yesterday_kills: 4,
        last_week_kills: 5,
        this_week_kills: 6,
        lifetime_honorable_kills: 7,
        lifetime_dishonorable_kills: 8,
        yesterday_contribution: 9,
        last_week_contribution: 10,
        this_week_contribution: 11,
        last_week_rank: 12,
        honor_rank_bar: 255
      }

      payload = Message.MsgInspectHonorStats.to_binary(%Message.MsgInspectHonorStats{guid: 7, player: player})

      assert payload ==
               <<7::little-size(64), 9, 3::little-size(16), 2::little-size(16), 4::little-size(16), 0::little-size(16),
                 5::little-size(16), 0::little-size(16), 6::little-size(16), 0::little-size(16), 7::little-size(32),
                 8::little-size(32), 9::little-size(32), 10::little-size(32), 11::little-size(32), 12::little-size(32),
                 255>>
    end

    test "encodes positive credit and signed dishonorable penalties" do
      for {type, expected} <- [{:honorable, 188}, {:dishonorable, -188}] do
        award = %Award{type: type, points: 188, victim_guid: 7, victim_rank: 5}
        payload = award |> Honor.credit() |> Message.SmsgPvpCredit.to_binary()
        assert payload == <<expected::little-signed-size(32), 7::little-size(64), 5::little-size(32)>>
      end
    end
  end

  defp character(race) do
    id = System.unique_integer([:positive])

    %Character{
      id: id,
      object: %Object{guid: id},
      unit: %Unit{race: race, level: 60, health: 100, max_health: 100, auras: []},
      player: %Player{coinage: 123},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, spline_nodes: []}
    }
  end
end
