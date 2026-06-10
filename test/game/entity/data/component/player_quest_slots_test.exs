defmodule ThistleTea.Game.Entity.Data.Component.PlayerQuestSlotsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Logic.QuestLog.Entry

  defp quest_slot_fields(player, target \\ :self) do
    player
    |> Player.to_list(target)
    |> Enum.filter(fn {field, _value, _meta} ->
      String.starts_with?(Atom.to_string(field), "quest_slot_")
    end)
  end

  test "emits nothing when the quest log is empty" do
    assert quest_slot_fields(%Player{quest_log: %{}}) == []
  end

  test "emits a 12-byte block at the right offset for an active quest" do
    player = %Player{quest_log: %{0 => %Entry{quest_id: 783}, 2 => %Entry{quest_id: 33}}}

    assert [
             {:quest_slot_1, <<783::little-size(32), 0::size(64)>>, {0x00C6, 3, :bytes}},
             {:quest_slot_3, <<33::little-size(32), 0::size(64)>>, {0x00CC, 3, :bytes}}
           ] = Enum.sort(quest_slot_fields(player))
  end

  test "cleared slots emit zero bytes so the client clears them" do
    player = %Player{quest_log: %{0 => :empty}}

    assert [{:quest_slot_1, <<0::size(96)>>, _meta}] = quest_slot_fields(player)
  end

  test "quest slots are private to the owning player" do
    player = %Player{quest_log: %{0 => %Entry{quest_id: 783}}}

    assert quest_slot_fields(player, :other) == []
  end
end
