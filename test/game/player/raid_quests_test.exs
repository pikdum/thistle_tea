defmodule ThistleTea.Game.Player.RaidQuestsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.WorldRef

  setup [:quests]

  describe "needed_items/1" do
    test "hides ordinary quest drops in a raid and restores them on departure", %{
      state: state,
      other: other,
      normal: normal,
      raid: raid
    } do
      assert Quests.needed_items(state.character) == MapSet.new([normal.id, raid.id])
      {:ok, _} = PartySystem.convert_raid(state.guid)
      assert Quests.needed_items(state.character) == MapSet.new([raid.id])
      Quests.sync_needed_items(state.character)
      assert Metadata.query(state.guid, [:needed_quest_items]).needed_quest_items == MapSet.new([raid.id])
      {:ok, _} = PartySystem.leave(other)
      Quests.sync_needed_items(state.character)
      assert Metadata.query(state.guid, [:needed_quest_items]).needed_quest_items == MapSet.new([normal.id, raid.id])
    end
  end

  describe "credit_kill_entry/3" do
    test "allows raid quest kills while preserving ordinary objectives until departure", %{
      state: state,
      other: other,
      normal: normal,
      raid: raid
    } do
      {:ok, _} = PartySystem.convert_raid(state.guid)
      credited = Quests.credit_kill_entry(state, 299, 123)
      assert QuestLog.get(credited.character.player.quest_log, normal.id).counts == %{}
      assert QuestLog.get(credited.character.player.quest_log, raid.id).counts == %{0 => 1}
      raid_id = raid.id
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgQuestupdateAddKill{quest_id: ^raid_id}}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgQuestupdateAddKill{}}}
      {:ok, _} = PartySystem.leave(other)
      resumed = Quests.credit_kill_entry(credited, 299, 124)
      assert QuestLog.get(resumed.character.player.quest_log, normal.id).counts == %{0 => 1}
    end
  end

  defp quests(_context) do
    guid = System.unique_integer([:positive, :monotonic])
    other = System.unique_integer([:positive, :monotonic])
    normal = %Quest{id: 900_000 + guid, required_items: [{0, 900_000 + guid, 1}], required_kills: [{0, 299, 2}]}
    raid = %{normal | id: normal.id + 1, type: 62, required_items: [{0, normal.id + 1, 1}]}

    for quest <- [normal, raid], do: :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
    {:ok, log} = QuestLog.add(%{}, normal.id)
    {:ok, log} = QuestLog.add(log, raid.id)
    :ok = PartySystem.invite(guid, "Leader", other)
    {:ok, _} = PartySystem.accept(other, "Other")

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, level: 10, race: 1, class: 1},
      player: %Player{quest_log: log},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    on_exit(fn ->
      PartySystem.leave(guid)
      PartySystem.leave(other)
      Presence.leave(character)
      for quest <- [normal, raid], do: :ets.delete(QuestLoader, {:quest, quest.id})
    end)

    %{state: %State{guid: guid, character: character}, other: other, normal: normal, raid: raid}
  end
end
