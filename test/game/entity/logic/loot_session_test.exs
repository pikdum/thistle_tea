defmodule ThistleTea.Game.Entity.Logic.LootSessionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.LootSession

  defp loot do
    %Loot{
      gold: 100,
      items: [
        %Loot.Item{slot: 0, item_id: 1604, quality: 2},
        %Loot.Item{slot: 1, item_id: 118, quality: 1}
      ]
    }
  end

  defp group(id, method), do: %{id: id, loot_method: method}

  describe "allowed?/3" do
    test "untapped loot is open to anyone" do
      session = LootSession.new(loot(), nil)
      assert LootSession.allowed?(session, 999, nil)
    end

    test "solo tap locks to the tapper" do
      session = LootSession.new(loot(), %{player: 100, group_id: nil})
      assert LootSession.allowed?(session, 100, nil)
      refute LootSession.allowed?(session, 200, nil)
    end

    test "group tap allows current group members" do
      session = LootSession.new(loot(), %{player: 100, group_id: 7})
      assert LootSession.allowed?(session, 200, group(7, 3))
      refute LootSession.allowed?(session, 300, group(8, 3))
      refute LootSession.allowed?(session, 300, nil)
    end

    test "round robin restricts to the assigned looter" do
      session =
        loot()
        |> LootSession.new(%{player: 100, group_id: 7})
        |> LootSession.assign_looter(200)

      assert LootSession.allowed?(session, 200, group(7, 1))
      refute LootSession.allowed?(session, 100, group(7, 1))
    end
  end

  describe "view/2" do
    test "hides blocked items from non-masters" do
      session =
        loot()
        |> LootSession.new(nil)
        |> LootSession.block_master_items(100, 2)

      assert [%{slot: 1}] = LootSession.view(session, 200).items
    end

    test "shows blocked items to the master with the master slot type" do
      session =
        loot()
        |> LootSession.new(nil)
        |> LootSession.block_master_items(100, 2)

      assert [%{slot: 0, slot_type: 2}, %{slot: 1, slot_type: 0}] = LootSession.view(session, 100).items
    end
  end

  describe "start_rolls/3" do
    test "blocks rolled items and creates one roll per item at or above threshold" do
      {session, rolls} = loot() |> LootSession.new(nil) |> LootSession.start_rolls(2, [1, 2])

      assert [%{slot: 0, item_id: 1604}] = rolls
      assert LootSession.rolls_pending?(session)
      assert [%{slot: 1}] = LootSession.view(session, 999).items
    end
  end

  describe "award_item/2" do
    test "unblocks and takes the item" do
      {session, _rolls} = loot() |> LootSession.new(nil) |> LootSession.start_rolls(2, [1, 2])

      assert {:ok, %Loot.Item{item_id: 1604}, session} = LootSession.award_item(session, 0)
      assert {:error, :already_looted} = LootSession.take_item(session, 0)
    end
  end

  describe "finished?/1" do
    test "requires empty loot and no pending rolls" do
      session = LootSession.new(loot(), nil)
      refute LootSession.finished?(session)

      {:ok, _gold, session} = LootSession.take_gold(session)
      {:ok, _item, session} = LootSession.take_item(session, 0)
      {:ok, _item, session} = LootSession.take_item(session, 1)
      assert LootSession.finished?(session)
    end

    test "pending rolls keep the session unfinished" do
      {session, _rolls} = loot() |> LootSession.new(nil) |> LootSession.start_rolls(2, [1, 2])
      {:ok, _gold, session} = LootSession.take_gold(session)
      {:ok, _item, session} = LootSession.take_item(session, 1)

      refute LootSession.finished?(session)

      {_roll, session} = LootSession.pop_roll(session, 0)
      {:ok, _item, session} = LootSession.award_item(session, 0)
      assert LootSession.finished?(session)
    end
  end

  describe "vote/4" do
    test "tracks votes through the embedded roll" do
      {session, _rolls} = loot() |> LootSession.new(nil) |> LootSession.start_rolls(2, [1, 2])

      assert {:ok, session, _roll} = LootSession.vote(session, 0, 1, :need)
      assert :error = LootSession.vote(session, 0, 1, :greed)
      assert :error = LootSession.vote(session, 99, 1, :need)
    end
  end
end
