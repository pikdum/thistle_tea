defmodule ThistleTea.Game.World.Entity.Player.MeetingStonesTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.MeetingStone
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.ClientProjection
  alias ThistleTea.Game.World.Entity.EventSink.Context, as: SinkContext
  alias ThistleTea.Game.World.Entity.Player.MeetingStones
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Entity.Registry
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  @entry 950_270

  setup [:players, :stone]

  describe "join/2" do
    test "queues at a live stone and rejects remote, dead, disabled, or foreign targets", context do
      state = hd(context.players)

      invalid = [
        %{state | character: %{state.character | unit: %{state.character.unit | health: 0}}},
        %{state | character: %{state.character | movement_block: %MovementBlock{position: {99.0, 0.0, 0.0, 0.0}}}},
        %{state | character: %{state.character | internal: %{state.character.internal | world: WorldRef.open(1)}}}
      ]

      for attempt <- invalid do
        assert MeetingStones.join(attempt, context.stone) == attempt
        refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgMeetingstoneSetqueue{status: 1}}}, 10
      end

      World.Metadata.update(context.stone, %{go_flags: 0x10})
      MeetingStones.join(state, context.stone)
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgMeetingstoneSetqueue{status: 1}}}, 10
      World.Metadata.update(context.stone, %{go_flags: 0})
      assert MeetingStones.join(state, context.stone) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMeetingstoneSetqueue{area: 1581, status: 1}}}
      MeetingStones.request(state, :leave)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMeetingstoneSetqueue{area: 0, status: 0}}}
    end
  end

  describe "queue/2" do
    test "commits automatic membership through the party owner and clears all queue records", context do
      Enum.each(context.players, &MeetingStones.queue(&1, 1581))
      [leader | _] = context.players
      group = PartySystem.group_of(leader.guid)
      assert Enum.map(group.members, & &1.guid) == Enum.map(context.players, & &1.guid)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMeetingstoneComplete{}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGroupList{members: members}}} when length(members) == 4
      state = :sys.get_state(PartySystem)
      assert MeetingStone.status(state.queue, state.party, leader.guid) == {:status, [leader.guid], 0, 5}
      assert Enum.all?(context.players, &(PartySystem.group_of(&1.guid).id == group.id))
    end

    test "retains a solo queue through owner loss and restores native status", context do
      [player | _] = context.players
      MeetingStones.queue(player, 1581)
      Registry.unregister(player.guid)
      send(PartySystem, :meeting_stone_tick)
      :sys.get_state(PartySystem)
      Registry.register(player.guid)
      MeetingStones.request(player, :info)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMeetingstoneSetqueue{area: 1581, status: 1}}}
      assert PartySystem.group_of(player.guid) == nil
    end
  end

  describe "scripted queue delivery" do
    test "retains the source world and uses the explicit player owner", context do
      [player | _] = context.players
      step = %ScriptStep{command: :meeting_stone, datalong: 1581}
      {character, _} = Script.run(player.character, Blackboard.new(), [step], nil, Context.new(0))
      [effect] = character.internal.events
      assert effect == %Effects.MeetingStoneQueue{player_guid: player.guid, area: 1581, world: WorldRef.open(0)}
      ClientProjection.emit(player.character, effect, nil)
      refute_received {:meeting_stone_queue, _, _}
      EventSink.emit(player.character, effect, SinkContext.new(self()))
      assert_received {:meeting_stone_queue, 1581, %WorldRef{map_id: 0}}
    end
  end

  defp players(_context) do
    states =
      Enum.map([1, 5, 8, 4, 3], fn class ->
        guid = System.unique_integer([:positive, :monotonic])

        character = %Character{
          id: guid,
          object: %Object{guid: guid},
          player: %Player{},
          unit: %Unit{health: 100, max_health: 100, level: 25, race: 1, class: class, auras: []},
          internal: %Internal{name: "Meeting#{guid}", world: WorldRef.open(0)},
          movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
        }

        Registry.register(guid)
        CharacterStore.put(character)
        Presence.enter(character, %{level: 25})
        %State{ready: true, guid: guid, character: character}
      end)

    on_exit(fn ->
      Enum.each(states, fn state ->
        PartySystem.meeting_stone(:leave, state.guid)
        PartySystem.leave(state.guid)
        Presence.leave(state.character)
        :ets.delete(CharacterStore, state.guid)
      end)
    end)

    %{players: states}
  end

  defp stone(_context) do
    template = %GameObjectTemplate{entry: @entry, type: 23, size: 1.0, flags: 0, faction: 0, data: [17, 26, 1581]}
    GameObjectTemplateLoader.put(template)
    object = GameObject.build_summoned(template, WorldRef.open(0), {1.0, 0.0, 0.0, 0.0})
    {:ok, _pid} = World.start_incarnation(object)

    on_exit(fn ->
      World.stop_entity(object.object.guid)
      :ets.delete(GameObjectTemplateLoader, @entry)
    end)

    %{stone: object.object.guid}
  end
end
