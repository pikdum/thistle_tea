defmodule ThistleTea.Game.Entity.Logic.Condition.LocalFactsTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [<<<: 2]

  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Condition, as: Evaluator
  alias ThistleTea.Game.Entity.Logic.Condition.Context
  alias ThistleTea.Game.Entity.Logic.Condition.Reason
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Entity.Logic.QuestLog.Entry

  describe "evaluate/2 local facts" do
    test "aura presence preserves effect-index semantics" do
      context = context(aura_ids: MapSet.new([100]), aura_effects: MapSet.new([{100, 1}]))

      assert met?(context, :aura, 100, -1)
      assert met?(context, :aura, 100, 1)
      refute met?(context, :aura, 100, 2)
    end

    test "inventory and equipment use projected stack totals" do
      context = context(item_counts: %{100 => 7}, equipped_item_ids: MapSet.new([200]))

      assert met?(context, :item, 100, 7)
      refute met?(context, :item, 100, 8)
      assert met?(context, :item_equipped, 200)
      refute met?(context, :item_equipped, 201)
    end

    test "team, race, class, skills, and reputation use semantic projections" do
      context =
        context(
          team: 469,
          race: 4,
          class: 11,
          skills: %{356 => %{value: 75}},
          reputation_ranks: %{529 => :honored}
        )

      assert met?(context, :team, 469)
      assert met?(context, :race_class, 1 <<< 3, 1 <<< 10)
      assert met?(context, :skill, 356, 75)
      refute met?(context, :skill, 356, 76)
      assert met?(context, :skill_below, 356, 76)
      assert met?(context, :skill_below, 164, 1)
      assert met?(context, :reputation_rank_min, 529, 5)
      assert met?(context, :reputation_rank_max, 529, 5)
    end

    test "quest state modes and availability use the preloaded pure quest catalog" do
      quest_log = %{
        0 => %Entry{quest_id: 10, status: :incomplete},
        1 => %Entry{quest_id: 11, status: :complete}
      }

      target =
        subject(
          level: 20,
          race: 4,
          class: 11,
          quest_log: quest_log,
          rewarded_quests: MapSet.new([12]),
          reputation: %{}
        )

      context = Context.new(target: target, quests: %{13 => %Quest{id: 13, min_level: 10}})

      assert met?(context, :quest_taken, 10, 0)
      assert met?(context, :quest_taken, 10, 1)
      refute met?(context, :quest_taken, 10, 2)
      assert met?(context, :quest_taken, 11, 2)
      assert met?(context, :quest_rewarded, 12)
      assert met?(context, :quest_none, 13)
      assert met?(context, :quest_available, 13)
    end

    test "missing quest catalog entries are unknown" do
      condition = %Condition{entry: 9, type: :quest_available, value1: 100}

      assert {:unknown, [%Reason{entry: 9, capability: {:missing_catalog, :quest, 100}}]} =
               Evaluator.evaluate(context(), condition)
    end

    test "game events, level, spells, patch, map, and time are boundary facts" do
      context =
        context(
          level: 20,
          spellbook: %{100 => :spell},
          map_id: 1,
          explored_areas: MapSet.new([42])
        )
        |> then(fn context ->
          %{context | world: %{map_id: 1, active_game_events: MapSet.new([7])}, content_patch: 10, now: ~T[12:30:00]}
        end)

      assert met?(context, :active_game_event, 7)
      assert met?(context, :level, 20, 0)
      assert met?(context, :level, 19, 1)
      assert met?(context, :level, 21, 2)
      assert met?(context, :spell, 100, 0)
      assert met?(context, :spell, 101, 1)
      assert met?(context, :content_patch, 10, 0)
      assert met?(context, :map_id, 1)
      assert met?(context, :local_time, 12, 0, 13, 0)
      assert met?(context, :area_explored, 42)
    end

    test "identity and unit state facts evaluate without boundary calls" do
      target =
        subject(
          kind: :player,
          player_owned?: true,
          area_id: 12,
          gender: 1,
          moving?: true,
          has_pet?: true,
          health: 51,
          max_health: 100,
          mana: 49,
          max_mana: 100,
          combat?: true,
          group?: true,
          alive?: true,
          argent_dawn_commission?: true
        )

      context = Context.new(target: target)

      assert met?(context, :area_id, 12)
      assert met?(context, :gender, 1)
      assert met?(context, :is_player, 0)
      assert met?(context, :is_player, 1)
      assert met?(context, :moving)
      assert met?(context, :has_pet)
      assert met?(context, :health_percent, 51, 0)
      assert met?(context, :mana_percent, 50, 2)
      assert met?(context, :in_combat)
      assert met?(context, :in_group)
      assert met?(context, :alive)
      assert met?(context, :argent_dawn_commission_aura)
    end

    test "zero maxima have explicit VMangos-compatible outcomes" do
      health_condition = %Condition{entry: 1, type: :health_percent, value1: 100, value2: 0}
      mana_condition = %Condition{type: :mana_percent, value1: 100, value2: 0}

      assert {:unknown, [%Reason{capability: {:invalid_maximum, :health}}]} =
               Evaluator.evaluate(context(health: 0, max_health: 0), health_condition)

      assert Evaluator.evaluate(context(mana: 0, max_mana: 0), mana_condition) == :met
    end

    test "bank-inclusive item counts are distinct from carried counts" do
      condition = %Condition{type: :item_with_bank, value1: 100, value2: 3}

      assert Evaluator.evaluate(context(item_counts_with_bank: %{100 => 3}), condition) == :met
      assert Evaluator.evaluate(context(item_counts_with_bank: %{100 => 2}), condition) == :unmet

      assert {:unknown, [%Reason{capability: {:missing_fact, :target, :item_counts_with_bank}}]} =
               Evaluator.evaluate(context(item_counts: %{100 => 10}), condition)
    end

    test "game-object state uses immutable owner projections" do
      context = context(kind: :game_object, go_spawned?: true, loot_state: 1, go_state: 2)

      assert met?(context, :object_spawned)
      assert met?(context, :object_loot_state, 1)
      refute met?(context, :object_loot_state, 2)
      assert met?(context, :object_go_state, 2)
      refute met?(context, :object_go_state, 0)
    end
  end

  defp met?(context, type, value1 \\ 0, value2 \\ 0, value3 \\ 0, value4 \\ 0) do
    condition = %Condition{type: type, value1: value1, value2: value2, value3: value3, value4: value4}

    Evaluator.evaluate(context, condition) ==
      :met
  end

  defp context(options \\ []), do: Context.new(source: subject(options), target: subject(options))
  defp subject(options), do: Subject.new(options)
end
