defmodule ThistleTea.Game.World.BattlegroundEffectSinkTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.Template
  alias ThistleTea.Game.Battleground.WarsongGulch
  alias ThistleTea.Game.Battleground.WarsongGulch.Player
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Battleground.EffectSink
  alias ThistleTea.Game.WorldRef

  test "publishes a nonzero active-match runtime to inside players" do
    guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
    assert {:ok, _owner} = Entity.register(guid)

    match = %WarsongGulch{
      world: WorldRef.instance(489, 7),
      client_instance_id: 7,
      bracket: 5,
      template: %Template{},
      started_at: Time.now() - 1_000,
      players: %{
        guid => %Player{guid: guid, name: "Debug", team: :alliance, status: :inside}
      }
    }

    assert :ok = EffectSink.emit(match, [%Effects.UpdateStatus{}])

    assert_receive {:"$gen_cast",
                    {:send_packet,
                     %Message.SmsgBattlefieldStatus{
                       map: 489,
                       bracket: 5,
                       client_instance_id: 7,
                       status: :in_progress,
                       time_one_ms: 0,
                       time_two_ms: elapsed_ms
                     }}}

    assert elapsed_ms >= 1_000
  end
end
