defmodule ThistleTea.Game.Entity.Logic.LootSessionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Logic.LootSession

  defp loot do
    %Loot{
      gold: 100,
      items: [
        %Loot.Item{slot: 0, item_id: 1604, quality: 2},
        %Loot.Item{slot: 1, item_id: 118, quality: 1},
        %Loot.Item{slot: 2, item_id: 929, quality: 1, quest_item: true}
      ]
    }
  end

  defp actor(guid, opts \\ []) do
    %Actor{
      guid: guid,
      group_id: Keyword.get(opts, :group_id),
      needed_items: MapSet.new(Keyword.get(opts, :needed_items, [])),
      distance: Keyword.get(opts, :distance, 0.0)
    }
  end

  describe "view/2" do
    test "untapped loot is open to nearby actors" do
      assert {:ok, %Loot{}} = loot() |> LootSession.new(nil) |> LootSession.view(actor(999))
    end

    test "solo tap locks every interaction to the tapper" do
      session = LootSession.new(loot(), %{player: 100, group_id: nil})

      assert {:ok, %Loot{}} = LootSession.view(session, actor(100))
      assert {:error, :no_permission} = LootSession.view(session, actor(200))
      assert {:error, :no_permission} = LootSession.take_item(session, actor(200), 0)
    end

    test "group tap allows current group members" do
      session = LootSession.new(loot(), %{player: 100, group_id: 7})

      assert {:ok, %Loot{}} = LootSession.view(session, actor(200, group_id: 7))
      assert {:error, :no_permission} = LootSession.view(session, actor(300, group_id: 8))
      assert {:error, :no_permission} = LootSession.view(session, actor(300))
    end

    test "round robin restricts viewing and taking to the assigned looter" do
      session =
        loot()
        |> LootSession.new(%{player: 100, group_id: 7})
        |> LootSession.configure_group(1)
        |> LootSession.assign_looter(200)

      assert {:ok, %Loot{}} = LootSession.view(session, actor(200, group_id: 7))
      assert {:error, :no_permission} = LootSession.view(session, actor(100, group_id: 7))
      assert {:error, :no_permission} = LootSession.take_item(session, actor(100, group_id: 7), 0)
    end

    test "rejects actors outside interaction distance" do
      session = LootSession.new(loot(), nil)
      assert {:error, :too_far} = LootSession.view(session, actor(100, distance: 5.1))
      assert {:error, :too_far} = LootSession.take_item(session, actor(100, distance: 5.1), 0)
    end

    test "filters quest items from the actor snapshot" do
      session = LootSession.new(loot(), nil)

      assert {:ok, %{items: items}} = LootSession.view(session, actor(100))
      refute Enum.any?(items, &(&1.item_id == 929))

      assert {:ok, %{items: items}} = LootSession.view(session, actor(100, needed_items: [929]))
      assert Enum.any?(items, &(&1.item_id == 929))
    end

    test "hides blocked items from non-masters" do
      session =
        loot()
        |> LootSession.new(nil)
        |> LootSession.block_master_items(100, 2)

      assert {:ok, %{items: items}} = LootSession.view(session, actor(200))
      assert Enum.map(items, & &1.slot) == [1]
    end

    test "shows blocked items to the master with the master slot type" do
      session =
        loot()
        |> LootSession.new(nil)
        |> LootSession.block_master_items(100, 2)

      assert {:ok, %{items: [%{slot: 0, slot_type: 2}, %{slot: 1, slot_type: 0}]}} =
               LootSession.view(session, actor(100))
    end
  end

  describe "visible?/2" do
    test "uses the same tap, assignment, and quest visibility policy without interaction distance" do
      session =
        %Loot{items: [%Loot.Item{slot: 0, item_id: 929, quest_item: true}]}
        |> LootSession.new(%{player: 100, group_id: 7})
        |> LootSession.configure_group(1)
        |> LootSession.assign_looter(200)

      projection = LootSession.project(session)

      refute LootSession.visible?(projection, actor(100, group_id: 7, needed_items: [929], distance: 100.0))
      refute LootSession.visible?(projection, actor(200, group_id: 7, distance: 100.0))
      assert LootSession.visible?(projection, actor(200, group_id: 7, needed_items: [929], distance: 100.0))
    end
  end

  describe "start_rolls/3" do
    test "blocks rolled items and creates one roll per item at or above threshold" do
      {session, rolls} = loot() |> LootSession.new(nil) |> LootSession.start_rolls(2, [1, 2])

      assert [%{slot: 0, item_id: 1604}] = rolls
      assert LootSession.pending?(session)
      assert {:ok, %{items: items}} = LootSession.view(session, actor(999))
      assert Enum.map(items, & &1.slot) == [1]
    end
  end

  describe "roll_award/3" do
    test "unblocks and takes the item for an eligible nearby winner" do
      {session, _rolls} = loot() |> LootSession.new(nil) |> LootSession.start_rolls(2, [1, 2])

      assert {:ok, %Loot.Item{item_id: 1604}, session} = LootSession.roll_award(session, actor(1), 0)
      assert {:error, :already_looted} = LootSession.take_item(session, actor(1), 0)
    end
  end

  describe "finished?/1" do
    test "requires empty loot and no pending rolls" do
      session = LootSession.new(loot(), nil)
      refute LootSession.finished?(session)

      {:ok, _gold, session} = LootSession.take_gold(session, actor(1))
      {:ok, _item, session} = LootSession.take_item(session, actor(1), 0)
      {:ok, _item, session} = LootSession.take_item(session, actor(1), 1)
      {:ok, _item, session} = LootSession.take_item(session, actor(1, needed_items: [929]), 2)
      assert LootSession.finished?(session)
    end

    test "pending rolls keep the session unfinished" do
      {session, _rolls} = loot() |> LootSession.new(nil) |> LootSession.start_rolls(2, [1, 2])
      {:ok, _gold, session} = LootSession.take_gold(session, actor(1))
      {:ok, _item, session} = LootSession.take_item(session, actor(1), 1)
      {:ok, _item, session} = LootSession.take_item(session, actor(1, needed_items: [929]), 2)

      refute LootSession.finished?(session)

      {_roll, session} = LootSession.pop_roll(session, 0)
      {:ok, _item, session} = LootSession.roll_award(session, actor(1), 0)
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
