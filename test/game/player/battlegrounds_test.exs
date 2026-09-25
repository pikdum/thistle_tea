defmodule ThistleTea.Game.Player.BattlegroundsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Battleground.Template
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Battlegrounds
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Battleground, as: BattlegroundLoader
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.WorldRef

  setup [:catalog, :players]

  describe "join/4" do
    test "native solo admission reports Deserter without queueing", %{leader: leader} do
      state = state(deserter(leader))
      assert join(state, false) == state
      assert_deserter_error()
      assert BattlegroundSystem.status(state.guid).status == :none
    end

    test "group admission rejects a penalized member atomically", %{leader: leader, member: member} do
      party(leader, member)
      Presence.sync(member, %{aura_stacks: %{26_013 => 1}})
      assert join(state(leader), true) == state(leader)
      assert_deserter_error()
      assert BattlegroundSystem.status(leader.object.guid).status == :none
      assert BattlegroundSystem.status(member.object.guid).status == :none

      Presence.sync(member, %{aura_stacks: %{}})
      join(state(leader), true)
      assert BattlegroundSystem.status(leader.object.guid).status == :wait_queue
      assert BattlegroundSystem.status(member.object.guid).status == :wait_queue
    end

    test "group admission reads the leader's current aura before its projection", %{leader: leader, member: member} do
      party(leader, member)
      join(state(deserter(leader)), true)
      assert_deserter_error()
      assert BattlegroundSystem.status(leader.object.guid).status == :none
      assert BattlegroundSystem.status(member.object.guid).status == :none
    end

    test "departure cannot requeue before the owner has exited its battleground", %{leader: leader} do
      character = %{leader | internal: %{leader.internal | world: WorldRef.instance(489, 123)}}
      join(state(character), false)
      assert BattlegroundSystem.status(leader.object.guid).status == :none
    end
  end

  describe "port/2" do
    test "rechecks Deserter and cancels an earlier invitation", %{leader: leader} do
      state = state(leader)
      assert {:ok, ^state} = Battlegrounds.debug_join_solo(state, 489)
      assert BattlegroundSystem.status(state.guid).status == :wait_join
      Battlegrounds.port(state(deserter(leader)), 1)
      assert_deserter_error()
      assert BattlegroundSystem.status(state.guid).status == :none
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgBattlefieldStatus{status: :none}}}
      refute_received {:"$gen_cast", {:start_teleport, _, _, _, _, _}}
    end
  end

  defp join(state, group?) do
    flag = if group?, do: 1, else: 0
    message = Message.CmsgBattlefieldJoin.from_binary(<<489::little-size(32), 0::little-size(32), flag>>)
    Message.CmsgBattlefieldJoin.handle(message, state)
  end

  defp assert_deserter_error do
    assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGroupJoinedBattleground{result: -2} = packet}}
    assert Message.SmsgGroupJoinedBattleground.to_binary(packet) == <<0xFFFFFFFE::little-size(32)>>
  end

  defp party(leader, member) do
    assert :ok = PartySystem.invite(leader.object.guid, leader.internal.name, member.object.guid)
    assert {:ok, _group} = PartySystem.accept(member.object.guid, member.internal.name)
  end

  defp catalog(_context) do
    key = {:map, 489}
    previous = :ets.lookup(BattlegroundLoader, key)

    template = %Template{
      type_id: 2,
      map_id: 489,
      min_players_per_team: 1,
      max_players_per_team: 10,
      min_level: 10,
      max_level: 60,
      alliance_start: {1.0, 2.0, 3.0, 4.0},
      horde_start: {5.0, 6.0, 7.0, 8.0}
    }

    :ets.insert(BattlegroundLoader, {key, template})

    on_exit(fn ->
      :ets.delete(BattlegroundLoader, key)
      :ets.insert(BattlegroundLoader, previous)
    end)

    :ok
  end

  defp players(_context) do
    leader = character()
    member = character()

    for character <- [leader, member] do
      Entity.register(character.object.guid)

      Presence.enter(character, %{
        name: character.internal.name,
        race: 1,
        level: 60,
        aura_stacks: %{}
      })
    end

    on_exit(fn ->
      for character <- [leader, member] do
        BattlegroundSystem.leave_queue(character.object.guid)
        PartySystem.leave(character.object.guid)
        Presence.leave(character)
      end
    end)

    %{leader: leader, member: member}
  end

  defp state(character), do: %{ready: true, guid: character.object.guid, character: character}

  defp deserter(character) do
    holder = %Holder{spell: %Spell{id: 26_013}, negative?: true}
    %{character | unit: %{character.unit | auras: [holder]}}
  end

  defp character do
    guid = System.unique_integer([:positive, :monotonic])

    %Character{
      id: guid,
      object: %Object{guid: guid},
      unit: %Unit{level: 60, race: 1, health: 100, max_health: 100},
      player: %Player{},
      internal: %Internal{world: WorldRef.open(0), name: "Player#{guid}"},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end
end
