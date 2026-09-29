defmodule ThistleTea.Game.Core.Loot.LootSessionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Condition.Context
  alias ThistleTea.Game.Core.Condition.Subject
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Item.ItemEligibility
  alias ThistleTea.Game.Core.Item.ItemProperty
  alias ThistleTea.Game.Core.Item.Proficiency
  alias ThistleTea.Game.Core.Loot
  alias ThistleTea.Game.Core.Loot.Actor
  alias ThistleTea.Game.Core.Loot.Commit
  alias ThistleTea.Game.Core.Loot.LootSession
  alias ThistleTea.Game.Core.Loot.Release

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
      distance: Keyword.get(opts, :distance, 0.0),
      condition_context: Keyword.get(opts, :condition_context),
      item_eligibility: Keyword.get(opts, :item_eligibility)
    }
  end

  describe "view/2" do
    test "revoked source access blocks visibility, money, reservations, and a pending transfer" do
      session = LootSession.new(loot(), nil)
      allowed = actor(100)
      denied = %{allowed | access_allowed?: false}
      token = make_ref()
      refute LootSession.visible?(session, denied)
      assert {:error, :no_permission} = LootSession.view(session, denied)
      assert {:error, :no_permission} = LootSession.take_gold(session, denied)
      assert {:error, :no_permission} = LootSession.reserve_item(session, denied, 0, token)
      assert {:ok, _reservation, reserved} = LootSession.reserve_item(session, allowed, 0, token)
      assert LootSession.validate_commit(reserved, allowed, token) == :ok
      assert LootSession.validate_commit(reserved, denied, token) == {:error, :no_permission}
      released = LootSession.release(reserved, token)
      assert {:ok, %Loot{}} = LootSession.view(released, allowed)
    end

    test "keeps a property's identity through reopen, rolls, and released reservations" do
      property = %ItemProperty{id: 1182, suffix: "of the Bear", enchantments: [72, 69, 0]}
      item = %Loot.Item{slot: 0, item_id: 1608, quality: 2, random_property: property}
      session = LootSession.new(%Loot{items: [item]}, nil)
      {rolling, [roll]} = LootSession.start_rolls(session, 2, [actor(1), actor(2)])
      assert roll.random_property_id == 1182

      token = make_ref()
      assert {:ok, reservation, reserved} = LootSession.reserve_roll(rolling, actor(1), 0, token)
      assert reservation.item.random_property == property
      released = reserved |> LootSession.release(token) |> LootSession.unblock_item(0)
      assert {:ok, %Loot{items: [^item]}} = LootSession.view(released, actor(1))
      assert {:ok, %Loot{items: [^item]}} = LootSession.view(released, actor(2))
    end

    test "untapped loot is open to nearby actors" do
      assert {:ok, %Loot{}} = loot() |> LootSession.new(nil) |> LootSession.view(actor(999))
    end

    test "solo tap locks every interaction to the tapper" do
      session = LootSession.new(loot(), %{player: 100, group_id: nil})

      assert {:ok, %Loot{}} = LootSession.view(session, actor(100))
      assert {:error, :no_permission} = LootSession.view(session, actor(200))
      assert {:error, :no_permission} = LootSession.reserve_item(session, actor(200), 0, make_ref())
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

      assert {:error, :no_permission} =
               LootSession.reserve_item(session, actor(100, group_id: 7), 0, make_ref())
    end

    test "rejects actors outside interaction distance" do
      session = LootSession.new(loot(), nil)
      assert {:error, :too_far} = LootSession.view(session, actor(100, distance: 5.1))
      assert {:error, :too_far} = LootSession.reserve_item(session, actor(100, distance: 5.1), 0, make_ref())
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

    test "shows conditioned items only to actors whose snapshot satisfies them" do
      condition = %Condition{entry: 1, type: :level, value1: 10, value2: 1}
      loot = %Loot{items: [%Loot.Item{slot: 0, item_id: 1604, condition: condition}]}
      session = LootSession.new(loot, nil)

      assert {:ok, %Loot{items: [%Loot.Item{item_id: 1604}]}} =
               LootSession.view(session, condition_actor(1, 10))

      assert {:error, :nothing_to_take} = LootSession.view(session, condition_actor(2, 9))
      assert {:error, :nothing_to_take} = LootSession.view(session, actor(3))
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

    test "includes only condition-eligible actors in a roll" do
      condition = %Condition{entry: 1, type: :level, value1: 10, value2: 1}
      loot = %Loot{items: [%Loot.Item{slot: 0, item_id: 1604, quality: 2, condition: condition}]}

      {_session, [roll]} =
        loot
        |> LootSession.new(nil)
        |> LootSession.start_rolls(2, [condition_actor(1, 10), condition_actor(2, 9)])

      assert roll.eligible == [1]
    end
  end

  describe "start_rolls/4" do
    test "Need Before Greed filters participation per item while Group Loot permits every actor" do
      loot = %Loot{
        items: [%Loot.Item{slot: 0, item_id: 100, quality: 2}, %Loot.Item{slot: 1, item_id: 101, quality: 2}]
      }

      templates = %{100 => %ItemTemplate{class: 2, subclass: 8}, 101 => %ItemTemplate{class: 4, subclass: 1}}
      warrior = roll_actor(1, %Proficiency{weapon_mask: 256, armor_mask: 2})
      mage = roll_actor(2, %Proficiency{armor_mask: 2})
      session = loot |> LootSession.new(nil) |> LootSession.configure_group(4)
      {rolling, rolls} = LootSession.start_rolls(session, 2, [warrior, mage], templates)
      assert Map.new(rolls, &{&1.slot, &1.eligible}) == %{0 => [1], 1 => [1, 2]}
      assert :error = LootSession.vote(rolling, 0, 2, :need)
      assert :error = LootSession.vote(rolling, 0, 2, :greed)
      assert {:ok, _, _} = LootSession.vote(rolling, 1, 2, :need)

      {_rolling, rolls} =
        session |> LootSession.configure_group(3) |> LootSession.start_rolls(2, [warrior, mage], templates)

      assert Enum.all?(rolls, &(&1.eligible == [1, 2]))
    end

    test "Need Before Greed combines usability, conditions, and source access" do
      condition = %Condition{entry: 1, type: :level, value1: 10, value2: 1}
      loot = %Loot{items: [%Loot.Item{slot: 0, item_id: 1604, quality: 2, condition: condition}]}
      eligible = roll_actor(1, Proficiency.all())
      allowed = %{condition_actor(1, 10) | item_eligibility: eligible.item_eligibility}
      denied = %{condition_actor(2, 9) | item_eligibility: eligible.item_eligibility}
      inaccessible = %{allowed | guid: 3, access_allowed?: false}
      session = loot |> LootSession.new(nil) |> LootSession.configure_group(4)

      {_session, [roll]} =
        LootSession.start_rolls(session, 2, [allowed, denied, inaccessible], %{1604 => %ItemTemplate{}})

      assert roll.eligible == [1]
    end

    test "leaves items available when nobody qualifies or eligibility is missing" do
      session = loot() |> LootSession.new(nil) |> LootSession.configure_group(4)
      unskilled = roll_actor(1, %Proficiency{})

      for {actors, templates} <- [
            {[unskilled], %{1604 => %ItemTemplate{class: 2, subclass: 8}}},
            {[unskilled], %{}},
            {[actor(1)], %{1604 => %ItemTemplate{}}},
            {[1], %{1604 => %ItemTemplate{}}}
          ] do
        assert {^session, []} = LootSession.start_rolls(session, 2, actors, templates)
        assert {:ok, %{item: %{item_id: 1604}}, _} = LootSession.reserve_item(session, actor(1), 0, make_ref())
      end
    end
  end

  defp roll_actor(guid, proficiency) do
    eligibility = %ItemEligibility{class: 1, race: 1, level: 60, highest_honor_rank: 0, proficiency: proficiency}
    actor(guid, item_eligibility: eligibility)
  end

  describe "reservations" do
    test "Need ownership survives lost reservations and preserves the exact item on retry" do
      property = %ItemProperty{id: 1182, suffix: "of the Bear", enchantments: [72, 69, 0]}
      item = %Loot.Item{slot: 0, item_id: 1608, quality: 2, random_property: property}
      {session, [_roll]} = LootSession.start_rolls(LootSession.new(%Loot{items: [item]}, nil), 2, [1, 2])
      {_roll, session} = LootSession.pop_roll(session, 0)
      session = LootSession.assign_need_winner(session, 0, 1)
      token = make_ref()
      assert {:error, :no_permission} = LootSession.reserve_roll(session, actor(2), 0, token)
      assert {:ok, _, reserved} = LootSession.reserve_roll(session, actor(1), 0, token)
      released = LootSession.release(reserved, token)
      refute LootSession.visible?(released, actor(2))
      refute LootSession.visible?(LootSession.project(released), actor(2))
      assert LootSession.visible?(LootSession.project(released), actor(1))
      assert {^released, []} = LootSession.start_rolls(released, 2, [1, 2])
      assert {:error, :already_looted} = LootSession.reserve_item(released, actor(2), 0, make_ref())
      assert {:ok, retry, reserved} = LootSession.reserve_item(released, actor(1), 0, make_ref())
      assert retry.item.random_property == property
      assert {:ok, awarded, committed} = LootSession.commit(reserved, %Commit{token: retry.token, actor_guid: 1})
      assert awarded.random_property == property
      assert LootSession.finished?(committed)
    end

    test "does not mark a direct item looted until the owner commits" do
      session = LootSession.new(loot(), nil)
      token = make_ref()

      assert {:ok, reservation, reserved} = LootSession.reserve_item(session, actor(1), 0, token)
      refute Enum.find(reserved.loot.items, &(&1.slot == 0)).looted
      assert LootSession.pending?(reserved)
      assert {:error, :already_looted} = LootSession.reserve_item(reserved, actor(1), 0, make_ref())

      commit = %Commit{token: token, actor_guid: reservation.actor_guid}
      assert {:ok, %Loot.Item{item_id: 1604}, committed} = LootSession.commit(reserved, commit)
      assert Enum.find(committed.loot.items, &(&1.slot == 0)).looted
      refute LootSession.pending?(committed)
    end

    test "release restores a direct item after inventory failure" do
      session = LootSession.new(loot(), nil)
      token = make_ref()
      {:ok, reservation, reserved} = LootSession.reserve_item(session, actor(1), 0, token)

      release = %Release{token: token, actor_guid: reservation.actor_guid}
      assert {:ok, released} = LootSession.release(reserved, release)
      assert {:ok, _reservation, _reserved} = LootSession.reserve_item(released, actor(1), 0, make_ref())
    end

    test "rejects a commit from anyone except the reserved actor" do
      session = LootSession.new(loot(), nil)
      token = make_ref()
      {:ok, _reservation, reserved} = LootSession.reserve_item(session, actor(1), 0, token)

      assert {:error, :invalid_reservation} =
               LootSession.commit(reserved, %Commit{token: token, actor_guid: 2})

      refute Enum.find(reserved.loot.items, &(&1.slot == 0)).looted
    end

    test "roll reservation restores the item as directly lootable on release" do
      {session, _rolls} = loot() |> LootSession.new(nil) |> LootSession.start_rolls(2, [1, 2])
      {_roll, session} = LootSession.pop_roll(session, 0)
      token = make_ref()

      assert {:ok, reservation, session} = LootSession.reserve_roll(session, actor(1), 0, token)
      release = %Release{token: token, actor_guid: reservation.actor_guid}
      assert {:ok, session} = LootSession.release(session, release)
      assert {:ok, _reservation, _session} = LootSession.reserve_item(session, actor(1), 0, make_ref())
    end

    test "master reservation remains master-controlled on release" do
      session =
        loot()
        |> LootSession.new(%{player: 100, group_id: 7})
        |> LootSession.configure_group(2)
        |> LootSession.block_master_items(100, 2)

      token = make_ref()
      giver = actor(100, group_id: 7)
      recipient = actor(200, group_id: 7)
      {:ok, reservation, reserved} = LootSession.reserve_master(session, giver, recipient, 0, token)

      release = %Release{token: token, actor_guid: reservation.actor_guid}
      assert {:ok, released} = LootSession.release(reserved, release)
      assert %Loot.Item{} = LootSession.blocked_item(released, 0)
      assert {:error, :already_looted} = LootSession.reserve_item(released, recipient, 0, make_ref())
    end

    test "master assignment and commit revalidate condition eligibility" do
      condition = %Condition{entry: 1, type: :level, value1: 10, value2: 1}

      session =
        %Loot{items: [%Loot.Item{slot: 0, item_id: 1604, quality: 2, condition: condition}]}
        |> LootSession.new(%{player: 100, group_id: 7})
        |> LootSession.configure_group(2)
        |> LootSession.block_master_items(100, 2)

      giver = condition_actor(100, 60, group_id: 7)
      eligible = condition_actor(200, 10, group_id: 7)
      ineligible = condition_actor(200, 9, group_id: 7)

      assert {:error, :no_permission} =
               LootSession.reserve_master(session, giver, ineligible, 0, make_ref())

      token = make_ref()
      assert {:ok, reservation, reserved} = LootSession.reserve_master(session, giver, eligible, 0, token)

      assert {:error, :no_permission} = LootSession.validate_commit(reserved, ineligible, reservation.token)
      assert :ok = LootSession.validate_commit(reserved, eligible, reservation.token)
    end
  end

  describe "finished?/1" do
    test "requires empty loot and no pending rolls" do
      session = LootSession.new(loot(), nil)
      refute LootSession.finished?(session)

      {:ok, _gold, session} = LootSession.take_gold(session, actor(1))
      {_item, session} = reserve_and_commit(session, actor(1), 0)
      {_item, session} = reserve_and_commit(session, actor(1), 1)
      {_item, session} = reserve_and_commit(session, actor(1, needed_items: [929]), 2)
      assert LootSession.finished?(session)
    end

    test "pending rolls keep the session unfinished" do
      {session, _rolls} = loot() |> LootSession.new(nil) |> LootSession.start_rolls(2, [1, 2])
      {:ok, _gold, session} = LootSession.take_gold(session, actor(1))
      {_item, session} = reserve_and_commit(session, actor(1), 1)
      {_item, session} = reserve_and_commit(session, actor(1, needed_items: [929]), 2)

      refute LootSession.finished?(session)

      {_roll, session} = LootSession.pop_roll(session, 0)
      token = make_ref()
      {:ok, reservation, session} = LootSession.reserve_roll(session, actor(1), 0, token)
      {:ok, _item, session} = LootSession.commit(session, %Commit{token: token, actor_guid: reservation.actor_guid})
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

  defp reserve_and_commit(session, %Actor{} = actor, slot) do
    token = make_ref()
    {:ok, reservation, session} = LootSession.reserve_item(session, actor, slot, token)
    {:ok, item, session} = LootSession.commit(session, %Commit{token: token, actor_guid: reservation.actor_guid})
    {item, session}
  end

  defp condition_actor(guid, level, opts \\ []) do
    context = Context.new(target: %Subject{guid: guid, kind: :player, level: level})
    actor(guid, Keyword.put(opts, :condition_context, context))
  end
end
