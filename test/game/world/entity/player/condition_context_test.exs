defmodule ThistleTea.Game.World.Entity.Player.ConditionContextTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Condition.InstanceDataSnapshot, as: Snapshot
  alias ThistleTea.Game.Core.Condition.Subject
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.Core.Reputation
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.Player.ConditionContext
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  describe "build/3" do
    test "collects requested server variables and preserves snapshot semantics" do
      condition = %Condition{type: :saved_variable, value1: 30_050, value2: 2}

      lookup = fn ->
        send(self(), :variables_read)
        %{30_050 => 2}
      end

      context = ConditionContext.build(character(), [condition], saved_variables: lookup)
      assert_receive :variables_read
      assert Condition.evaluate(context, condition) == :met
      fresh = ConditionContext.build(character(), [condition], saved_variables: fn -> %{30_050 => 3} end)
      assert Condition.evaluate(fresh, condition) == :unmet
      assert Condition.evaluate(context, condition) == :met
      ConditionContext.build(character(), [], saved_variables: lookup)
      refute_received :variables_read
      snapshot = ConditionContext.snapshot(character(), saved_variables: lookup)
      assert_receive :variables_read
      assert Condition.evaluate(snapshot, condition) == :met
    end

    test "quest availability alone requests the active event snapshot" do
      condition = %Condition{type: :quest_available, value1: 300}

      context =
        ConditionContext.build(character(), [condition],
          quest_lookup: fn 300 -> %Quest{id: 300, event_id: 12} end,
          reputation_standings: fn _ -> %{} end,
          game_events: fn -> [12] end
        )

      assert context.world.active_game_events == MapSet.new([12])
      assert Condition.evaluate(context, condition) == :met
      assert Condition.evaluate(%{context | world: %{active_game_events: MapSet.new()}}, condition) == :unmet
    end

    test "projects current visible rank and refreshes it after rank loss" do
      condition = %Condition{type: :pvp_rank, value1: 6, value2: 1}
      character = character()
      character = %{character | player: %{character.player | honor_rank: 10, highest_honor_rank: 18}}
      context = ConditionContext.build(character, [condition])
      assert context.target.honor_rank == 6
      assert Condition.evaluate(context, condition) == :met

      demoted = %{character | player: %{character.player | honor_rank: 9}}
      assert ConditionContext.refresh_subject(demoted, context.target).honor_rank == 5
      assert Condition.evaluate(ConditionContext.build(demoted, [condition]), condition) == :unmet
    end

    test "uses owner-published rank for swapped player sources" do
      guid = System.unique_integer([:positive, :monotonic])
      Metadata.put(guid, %{honor_rank: 18})
      on_exit(fn -> Metadata.delete(guid) end)
      condition = %Condition{type: :pvp_rank, value1: 14, swap_targets?: true}
      context = ConditionContext.build(character(), [condition], source: %Subject{guid: guid, kind: :player})
      assert Condition.evaluate(context, condition) == :met
    end

    test "collects requested item totals, catalogs, and world facts once" do
      owner = self()

      conditions = [
        %Condition{type: :item, value1: 100, value2: 5},
        %Condition{type: :item_with_bank, value1: 100, value2: 7},
        %Condition{type: :item_equipped, value1: 200},
        %Condition{type: :quest_available, value1: 300},
        %Condition{type: :active_game_event, value1: 7}
      ]

      context =
        ConditionContext.build(character(), conditions,
          item_lookup: fn guid -> item(guid) end,
          quest_lookup: fn 300 ->
            send(owner, :quest_lookup)
            %Quest{id: 300}
          end,
          reputation_standings: fn _character ->
            send(owner, :reputation)
            %{}
          end,
          game_events: fn ->
            send(owner, :game_events)
            [7]
          end
        )

      assert Condition.evaluate(context, Enum.at(conditions, 0)) == :met
      assert Condition.evaluate(context, Enum.at(conditions, 1)) == :met
      assert Condition.evaluate(context, Enum.at(conditions, 2)) == :met
      assert Condition.evaluate(context, Enum.at(conditions, 3)) == :met
      assert Condition.evaluate(context, Enum.at(conditions, 4)) == :met
      assert_received :quest_lookup
      assert_received :reputation
      assert_received :game_events
      refute_received _message
    end

    test "does not invoke unrelated boundary collectors" do
      context =
        ConditionContext.build(character(), [%Condition{type: :level, value1: 20}],
          item_lookup: fn _guid -> flunk("item lookup was not planned") end,
          quest_lookup: fn _quest_id -> flunk("quest lookup was not planned") end,
          reputation_standings: fn _character -> flunk("reputation lookup was not planned") end,
          game_events: fn -> flunk("game-event lookup was not planned") end,
          group_lookup: fn _guid -> flunk("group lookup was not planned") end,
          instance_data: fn _world, _fields -> flunk("instance data lookup was not planned") end,
          zone_and_area: fn _map_id, _position -> flunk("zone lookup was not planned") end
        )

      assert context.target.level == 20
    end

    test "distinguishes items inside purchased bank bags from carried items" do
      banked = Item.build(%ItemTemplate{entry: 300}, 31, stack_count: 2)
      bag = Item.build(%ItemTemplate{entry: 400, inventory_type: 18, container_slots: 6, class: 1}, 30)
      bag = put_in(bag.container.slot_1, banked.object.guid)

      character = %{
        character()
        | player: %{character().player | inv1: nil, bank1: nil, bank_bag1: 30, bank_bag_slots: 1}
      }

      items = %{30 => bag, 31 => banked}

      carried = %Condition{type: :item, value1: 300, value2: 1}
      inclusive = %Condition{type: :item_with_bank, value1: 300, value2: 2}
      context = ConditionContext.build(character, [carried, inclusive], item_lookup: &Map.get(items, &1))

      assert Condition.evaluate(context, carried) == :unmet
      assert Condition.evaluate(context, inclusive) == :met
    end

    test "distinguishes base bank items from carried items" do
      character = %{character() | player: %{character().player | inv1: nil, bank1: 30}}
      carried = %Condition{type: :item, value1: 100, value2: 1}
      inclusive = %Condition{type: :item_with_bank, value1: 100, value2: 2}
      context = ConditionContext.build(character, [carried, inclusive], item_lookup: &item/1)

      assert Condition.evaluate(context, carried) == :unmet
      assert Condition.evaluate(context, inclusive) == :met
    end

    test "matches both authoritative zone and sub-area IDs" do
      zone = %Condition{type: :area_id, value1: 12}
      area = %Condition{type: :area_id, value1: 34}

      context =
        ConditionContext.build(character(), [zone, area], zone_and_area: fn 1, {1.0, 2.0, 3.0} -> {12, 34} end)

      assert Condition.evaluate(context, zone) == :met
      assert Condition.evaluate(context, area) == :met
    end

    test "the default source uses the current owner snapshot before presence catches up" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
      character = %{character() | object: %Object{guid: guid}}
      condition = %Condition{type: :area_id, value1: 12}
      owner = self()
      SpatialHash.insert(:players, guid, WorldRef.open(451), 0.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, guid) end)

      context =
        ConditionContext.build(character, [condition],
          zone_and_area: fn 1, {1.0, 2.0, 3.0} ->
            send(owner, :zone_lookup)
            {12, 34}
          end
        )

      assert context.source == context.target
      assert context.source.position == {1.0, 2.0, 3.0, 0.0}
      assert context.source.zone_id == 12
      assert_received :zone_lookup
      refute_received :zone_lookup
    end

    test "collects planned environmental facts for an interacting world source" do
      source_guid = Guid.from_low_guid(:mob, 123, System.unique_integer([:positive, :monotonic]))
      source = %Subject{guid: source_guid, kind: :mob, entry: 123}
      condition = %Condition{entry: 77, type: :nearby_creature, value1: 456, value2: 30}
      owner = self()
      Metadata.put(source_guid, %{db_guid: 456})
      on_exit(fn -> Metadata.delete(source_guid) end)

      context =
        ConditionContext.build(character(), [condition],
          source: source,
          condition_results: fn world, passed_source, target, conditions ->
            send(owner, {:collected, world, passed_source, target, conditions})
            %{77 => true}
          end
        )

      assert Condition.evaluate(context, condition) == :met
      assert context.source.db_guid == 456

      assert_received {:collected, %WorldRef{map_id: 1}, ^source_guid, 1, [^condition]}
    end

    test "retains an explicitly absent source without world lookups" do
      owner = self()
      condition = %Condition{entry: 77, type: :map_event_active, value1: 12}

      context =
        ConditionContext.build(character(), [condition],
          source: nil,
          condition_results: fn world, source_guid, target_guid, conditions ->
            send(owner, {:collected, world, source_guid, target_guid, conditions})
            %{77 => false}
          end
        )

      assert context.source == nil
      assert %Subject{guid: 1, kind: :player} = context.target
      assert_received {:collected, %WorldRef{map_id: 1}, nil, 1, [^condition]}
    end

    test "preserves default and explicit subject sources" do
      character = character()
      explicit = %Subject{guid: 42, kind: :creature, entry: 7}

      assert %Subject{guid: 1, kind: :player} = ConditionContext.build(character, []).source

      assert %Subject{guid: 42, kind: :creature, entry: 7} =
               ConditionContext.build(character, [], source: explicit).source
    end

    test "source-dependent conditions with an absent source are unknown" do
      condition = %Condition{entry: 77, type: :source_entry, value1: 7}
      context = ConditionContext.build(character(), [condition], source: nil)

      assert {:unknown, _reasons} = Condition.evaluate(context, condition)
    end

    test "batches deduplicated instance fields for the exact copy alongside game events" do
      owner = self()
      world = WorldRef.instance(329, 41)
      character = %{character() | internal: %{character().internal | world: world}}

      conditions = [
        %Condition{type: :instance_data, value1: 7, value2: 2},
        %Condition{type: :instance_data, value1: 7, value2: 2},
        %Condition{type: :active_game_event, value1: 9}
      ]

      context =
        ConditionContext.build(character, conditions,
          source: nil,
          game_events: fn -> [9] end,
          instance_data: fn passed_world, fields ->
            send(owner, {:instance_data, passed_world, fields})
            snapshot(passed_world, %{7 => {:ok, 2}})
          end
        )

      assert context.source == nil
      assert context.world.active_game_events == MapSet.new([9])
      assert Condition.evaluate(context, Enum.at(conditions, 0)) == :met
      assert_received {:instance_data, ^world, [7]}
      refute_received {:instance_data, _, _}
    end

    test "preserves unsupported instance fields for fail-closed evaluation" do
      world = WorldRef.instance(329, 42)
      character = %{character() | internal: %{character().internal | world: world}}
      condition = %Condition{type: :instance_data, value1: 5, value2: 3}

      context =
        ConditionContext.build(character, [condition],
          instance_data: fn ^world, [5] -> snapshot(world, %{5 => {:error, {:unsupported_field, 5}}}) end
        )

      assert {:unknown, _reasons} = Condition.evaluate(context, condition)
    end
  end

  describe "refresh_subject/3" do
    test "refreshes player-owned facts without discarding published inventory totals" do
      previous = %Subject{
        item_counts: %{100 => 5},
        item_counts_with_bank: %{100 => 7},
        equipped_item_ids: MapSet.new([200])
      }

      refreshed = ConditionContext.refresh_subject(character(), previous, item_lookup: fn _guid -> nil end)

      assert refreshed.item_counts == %{100 => 5}
      assert refreshed.item_counts_with_bank == %{100 => 7}
      assert refreshed.equipped_item_ids == MapSet.new([200])
      assert refreshed.level == 20
      assert refreshed.quest_log == %{}
    end
  end

  defp character do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 20, race: 1, class: 1, health: 100, max_health: 100, power1: 0, max_power1: 0, auras: []},
      player: %Player{
        inv1: 10,
        bank1: 30,
        mainhand: 20,
        skills: %{},
        quest_log: %{},
        rewarded_quests: MapSet.new(),
        reputation: %Reputation{}
      },
      movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}},
      internal: %Internal{world: WorldRef.open(1), spellbook: %{}}
    }
  end

  defp item(10), do: Item.build(%ItemTemplate{entry: 100}, 10, stack_count: 5)
  defp item(20), do: Item.build(%ItemTemplate{entry: 200}, 20)
  defp item(30), do: Item.build(%ItemTemplate{entry: 100}, 30, stack_count: 2)
  defp item(_guid), do: nil

  defp snapshot(world, fields) do
    %Snapshot{world: world, status: :available, script_name: "instance_stratholme", fields: fields}
  end
end
