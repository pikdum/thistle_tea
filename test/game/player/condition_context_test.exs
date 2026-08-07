defmodule ThistleTea.Game.Player.ConditionContextTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Data.Reputation
  alias ThistleTea.Game.Entity.Logic.Condition, as: Evaluator
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Player.ConditionContext
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  describe "build/3" do
    test "collects requested item totals, catalogs, and world facts once" do
      owner = self()

      conditions = [
        %Condition{type: :item, value1: 100, value2: 5},
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

      assert Evaluator.evaluate(context, Enum.at(conditions, 0)) == :met
      assert Evaluator.evaluate(context, Enum.at(conditions, 1)) == :met
      assert Evaluator.evaluate(context, Enum.at(conditions, 2)) == :met
      assert Evaluator.evaluate(context, Enum.at(conditions, 3)) == :met
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
          zone_and_area: fn _map_id, _position -> flunk("zone lookup was not planned") end
        )

      assert context.target.level == 20
    end

    test "matches both authoritative zone and sub-area IDs" do
      zone = %Condition{type: :area_id, value1: 12}
      area = %Condition{type: :area_id, value1: 34}

      context =
        ConditionContext.build(character(), [zone, area], zone_and_area: fn 1, {1.0, 2.0, 3.0} -> {12, 34} end)

      assert Evaluator.evaluate(context, zone) == :met
      assert Evaluator.evaluate(context, area) == :met
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

      assert Evaluator.evaluate(context, condition) == :met
      assert context.source.db_guid == 456

      assert_received {:collected, %WorldRef{map_id: 1}, ^source_guid, 1, [^condition]}
    end
  end

  describe "refresh_subject/3" do
    test "refreshes player-owned facts without discarding published inventory totals" do
      previous = %Subject{item_counts: %{100 => 5}, equipped_item_ids: MapSet.new([200])}
      refreshed = ConditionContext.refresh_subject(character(), previous, item_lookup: fn _guid -> nil end)

      assert refreshed.item_counts == %{100 => 5}
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
  defp item(_guid), do: nil
end
