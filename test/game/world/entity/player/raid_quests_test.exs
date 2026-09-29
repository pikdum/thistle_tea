defmodule ThistleTea.Game.World.Entity.Player.RaidQuestsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.Core.Quest.QuestLog
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Quests
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.System.Party, as: PartySystem

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

  describe "credit_cast/3" do
    test "ignores player targets and retains matching creature credit in a raid", %{state: state, normal: quest} do
      quest = %{quest | required_entity_objectives: [{0, :creature, 299, 10_292, 2}]}
      :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
      {:ok, _} = PartySystem.convert_raid(state.guid)

      assert Quests.credit_cast(state, [state.guid], 10_292) == state

      creature = Guid.from_low_guid(:creature, 299, 1)
      credited = Quests.credit_cast(state, [state.guid, creature], 10_292)
      assert QuestLog.get(credited.character.player.quest_log, quest.id).counts == %{0 => 1}
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
