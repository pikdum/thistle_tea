defmodule ThistleTea.Game.Core.ConditionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Condition.Context
  alias ThistleTea.Game.Core.Condition.InstanceDataSnapshot, as: Snapshot
  alias ThistleTea.Game.Core.Condition.Reason
  alias ThistleTea.Game.Core.Condition.Subject
  alias ThistleTea.Game.Core.WorldRef

  describe "evaluate/2" do
    test "compares server variables independently of source, target, and map" do
      context = Context.new(world: %{saved_variables: %{30_050 => 2}})
      condition = %Condition{type: :saved_variable, value1: 30_050, value2: 2}

      for comparison <- 0..2 do
        assert Condition.evaluate(context, %{condition | value3: comparison}) == :met
      end

      assert Condition.evaluate(context, %{condition | value2: 3, value3: 1}) == :unmet
      assert Condition.evaluate(context, %{condition | value2: 1, value3: 2}) == :unmet
      assert Condition.evaluate(context, %{condition | swap_targets?: true}) == :met
      assert Condition.evaluate(context, %{condition | reverse?: true}) == :unmet
      assert Condition.evaluate(context, %{condition | value1: 30_056, value2: 0}) == :met

      assert {:unknown, [%Reason{capability: :invalid_comparison}]} =
               Condition.evaluate(context, %{condition | value3: 3})
    end

    test "an absent server-variable snapshot stays unknown under negation" do
      condition = %Condition{type: :saved_variable, value1: 30_050, value2: 0}

      for reverse? <- [true, false] do
        assert {:unknown, [%Reason{capability: {:missing_fact, :world, :saved_variables}}]} =
                 Condition.evaluate(Context.new(), %{condition | reverse?: reverse?})
      end
    end

    test "compares visible PvP rank with inclusive bounds and target swapping" do
      context =
        Context.new(
          target: Subject.new(kind: :player, honor_rank: 6),
          source: Subject.new(kind: :player, honor_rank: 0)
        )

      condition = %Condition{type: :pvp_rank, value1: 6}

      for comparison <- 0..2 do
        assert Condition.evaluate(context, %{condition | value2: comparison}) == :met
      end

      assert Condition.evaluate(context, %{condition | value1: 7, value2: 1}) == :unmet
      assert Condition.evaluate(context, %{condition | value1: 5, value2: 2}) == :unmet
      assert Condition.evaluate(context, %{condition | swap_targets?: true}) == :unmet
      assert Condition.evaluate(context, %{condition | swap_targets?: true, reverse?: true}) == :met
      assert Condition.evaluate(context, %{condition | value1: 0, swap_targets?: true}) == :met

      assert {:unknown, [%Reason{capability: :invalid_comparison}]} =
               Condition.evaluate(context, %{condition | value2: 3})
    end

    test "distinguishes missing rank from unranked players and non-player targets" do
      condition = %Condition{type: :pvp_rank, value1: 0}
      assert Condition.evaluate(Context.new(target: Subject.new(kind: :player, honor_rank: 0)), condition) == :met
      assert Condition.evaluate(Context.new(target: Subject.new(kind: :creature)), condition) == :unmet

      assert {:unknown, [%Reason{capability: {:missing_fact, :target, :honor_rank}}]} =
               Condition.evaluate(Context.new(target: Subject.new(kind: :player)), condition)
    end

    test "nil and none are met" do
      context = Context.new()

      assert Condition.evaluate(context, nil) == :met
      assert Condition.evaluate(context, %Condition{type: :none}) == :met
    end

    test "source entry and db guid match any nonzero raw value" do
      context = Context.new(source: Subject.new(entry: 38, db_guid: 80_152))

      assert Condition.evaluate(context, %Condition{type: :source_entry, value1: 38}) == :met
      assert Condition.evaluate(context, %Condition{type: :source_entry, value1: 1, value3: 38}) == :met
      assert Condition.evaluate(context, %Condition{type: :source_entry, value1: 39}) == :unmet
      assert Condition.evaluate(context, %Condition{type: :db_guid, value1: 1, value2: 80_152}) == :met
    end

    test "has flag checks a flag field of the source" do
      context = Context.new(source: Subject.new(flags: %{147 => 0x3}))

      assert Condition.evaluate(context, %Condition{type: :has_flag, value1: 147, value2: 0x2}) == :met
      assert Condition.evaluate(context, %Condition{type: :has_flag, value1: 147, value2: 0x4}) == :unmet

      assert {:unknown, [%Reason{capability: {:missing_fact, :source, :flags}}]} =
               Condition.evaluate(context, %Condition{type: :has_flag, value1: 46, value2: 0x2})
    end

    test "missing facts are explicit unknown reasons" do
      condition = %Condition{entry: 42, type: :db_guid, value1: 80_152}

      assert {:unknown, [%Reason{entry: 42, type: :db_guid, capability: {:missing_fact, :source, :db_guid}}]} =
               Condition.evaluate(Context.new(source: Subject.new()), condition)
    end

    test "precomputed boundary facts preserve explicit unknown results" do
      condition = %Condition{entry: 42, type: :nearby_creature}
      unknown = {:unknown, [%Reason{entry: 42, type: :nearby_creature, capability: :position}]}
      context = Context.new(environment: %{condition_results: %{42 => unknown}})

      assert Condition.evaluate(context, condition) == unknown
    end

    test "precomputed boundary facts keep structurally distinct unresolved entries" do
      first = %Condition{type: :nearby_creature, value1: 1}
      second = %Condition{type: :nearby_creature, value1: 2}

      context =
        Context.new(environment: %{condition_results: %{first => :met, second => :unmet}})

      assert Condition.evaluate(context, first) == :met
      assert Condition.evaluate(context, second) == :unmet
    end

    test "reputation bounds use the projected rank" do
      context = Context.new(target: Subject.new(reputation_ranks: %{529 => :honored}))

      assert Condition.evaluate(context, %Condition{type: :reputation_rank_min, value1: 529, value2: 5}) == :met
      assert Condition.evaluate(context, %Condition{type: :reputation_rank_min, value1: 529, value2: 6}) == :unmet
      assert Condition.evaluate(context, %Condition{type: :reputation_rank_max, value1: 529, value2: 5}) == :met
    end

    test "target swapping happens before a tree is evaluated" do
      context = Context.new(source: Subject.new(entry: 38), target: Subject.new(entry: 39))

      assert Condition.evaluate(context, %Condition{type: :source_entry, value1: 39, swap_targets?: true}) == :met

      tree = %Condition{
        type: :and,
        swap_targets?: true,
        children: [%Condition{type: :source_entry, value1: 39}]
      }

      assert Condition.evaluate(context, tree) == :met
    end

    test "reverse negates met and unmet but preserves unknown" do
      context = Context.new(source: Subject.new(entry: 38))

      assert Condition.evaluate(context, %Condition{type: :source_entry, value1: 38, reverse?: true}) == :unmet
      assert Condition.evaluate(context, %Condition{type: :source_entry, value1: 39, reverse?: true}) == :met

      assert {:unknown, [%Reason{capability: {:missing_fact, :target, :level}}]} =
               Condition.evaluate(context, %Condition{type: :level, reverse?: true})
    end

    test "and uses three-valued truth tables" do
      assert_combinations(:and, [
        {[:met, :met], :met},
        {[:met, :unknown], :unknown},
        {[:unknown, :unknown], :unknown},
        {[:unmet, :unknown], :unmet},
        {[:unmet, :met], :unmet}
      ])
    end

    test "or uses three-valued truth tables" do
      assert_combinations(:or, [
        {[:unmet, :unmet], :unmet},
        {[:unmet, :unknown], :unknown},
        {[:unknown, :unknown], :unknown},
        {[:met, :unknown], :met},
        {[:met, :unmet], :met}
      ])
    end

    test "not preserves unknown" do
      tree = %Condition{type: :not, children: [leaf(:unknown)]}

      assert {:unknown, _reasons} = Condition.evaluate(context(), tree)
    end

    test "unresolved and unknown upstream types stay unknown" do
      assert {:unknown, [%Reason{capability: :unresolved_tree}]} =
               Condition.evaluate(context(), Condition.unresolved(10))

      assert {:unknown, [%Reason{capability: {:unsupported_condition_type, 99}}]} =
               Condition.evaluate(context(), %Condition{type: {:unsupported, 99}})
    end
  end

  describe "specialize/2" do
    test "decides database guid and content patch leaves from a spawn's fixed facts" do
      context = spawn_context(80_152)

      assert Condition.specialize(context, db_guid([80_184, 80_152])) == :met
      assert Condition.specialize(context, db_guid([80_184])) == :unmet
      assert Condition.specialize(context, %{db_guid([80_184]) | reverse?: true}) == :met
      assert Condition.specialize(context, %Condition{type: :content_patch, value1: 10, value2: 0}) == :met
      assert Condition.specialize(spawn_context(nil), db_guid([80_152])) == db_guid([80_152])
    end

    test "folds combinators around decided leaves and keeps what the spawn cannot decide" do
      context = spawn_context(80_152)
      level = %Condition{entry: 7, type: :level, value1: 20, value2: 0}

      assert Condition.specialize(context, %Condition{type: :or, children: [db_guid([1]), db_guid([80_152])]}) == :met
      assert Condition.specialize(context, %Condition{type: :or, children: [db_guid([1]), db_guid([2])]}) == :unmet
      assert Condition.specialize(context, %Condition{type: :and, children: [db_guid([1]), level]}) == :unmet
      assert Condition.specialize(context, %Condition{type: :not, children: [db_guid([80_152])]}) == :unmet

      assert Condition.specialize(context, %Condition{type: :or, reverse?: true, children: [db_guid([80_152])]}) ==
               :unmet

      assert %Condition{type: :and, children: [^level]} =
               Condition.specialize(context, %Condition{type: :and, children: [db_guid([80_152]), level]})

      assert %Condition{type: :or, children: [^level]} =
               Condition.specialize(context, %Condition{type: :or, children: [db_guid([1]), level]})
    end

    test "leaves read through swapped targets stay undecided" do
      swapped = %{db_guid([80_152]) | swap_targets?: true}
      tree = %Condition{type: :or, swap_targets?: true, children: [db_guid([80_152])]}

      assert Condition.specialize(spawn_context(80_152), swapped) == swapped
      assert Condition.specialize(spawn_context(80_152), tree) == tree
    end

    test "a specialized tree evaluates exactly like the original" do
      level = %Condition{entry: 7, type: :level, value1: 20, value2: 0}

      trees = [
        %Condition{type: :and, children: [db_guid([80_152]), level]},
        %Condition{type: :or, children: [db_guid([1]), %{level | reverse?: true}]},
        %Condition{type: :not, children: [%Condition{type: :and, children: [level, db_guid([80_152])]}]},
        %Condition{type: :or, children: [db_guid([1]), %Condition{entry: 8, type: :level}]}
      ]

      for tree <- trees, target_level <- [20, 21, nil] do
        runtime =
          Context.new(
            source: Subject.new(db_guid: 80_152),
            target: Subject.new(level: target_level),
            content_patch: 10
          )

        specialized = Condition.specialize(spawn_context(80_152), tree)
        expected = Condition.evaluate(runtime, tree)
        actual = if is_struct(specialized, Condition), do: Condition.evaluate(runtime, specialized), else: specialized
        assert actual == expected
      end
    end
  end

  describe "compare/3" do
    test "implements VMangos comparison modes" do
      assert Condition.compare(5, 5, 0)
      assert Condition.compare(5, 4, 1)
      assert Condition.compare(5, 6, 2)
      refute Condition.compare(5, 4, 0)
      refute Condition.compare(5, 6, 1)
      refute Condition.compare(5, 4, 2)
      assert Condition.compare(5, 5, 3) == {:error, :invalid_comparison}
    end
  end

  describe "instance_data" do
    test "evaluates equality and ordered comparisons from a supplied snapshot" do
      context = instance_context(%{7 => {:ok, 2}})

      assert Condition.evaluate(context, instance_condition(2, 0)) == :met
      assert Condition.evaluate(context, instance_condition(1, 0)) == :unmet
      assert Condition.evaluate(context, instance_condition(1, 1)) == :met
      assert Condition.evaluate(context, instance_condition(3, 1)) == :unmet
      assert Condition.evaluate(context, instance_condition(3, 2)) == :met
      assert Condition.evaluate(context, instance_condition(1, 2)) == :unmet
    end

    test "compares an unwritten registered field as zero" do
      assert Condition.evaluate(instance_context(%{7 => {:ok, 0}}), instance_condition(0, 0)) == :met
    end

    test "treats definitive absence as unmet" do
      condition = instance_condition(0, 0)

      assert Condition.evaluate(instance_context(:no_instance_script), condition) == :unmet
      assert Condition.evaluate(instance_context(:open_world), condition) == :unmet
    end

    test "keeps unsupported and missing capabilities structured unknowns" do
      condition = instance_condition(0, 0)

      assert {:unknown, [%Reason{capability: {:unsupported_instance_field, 7}}]} =
               Condition.evaluate(instance_context(%{7 => {:error, {:unsupported_field, 7}}}), condition)

      assert {:unknown, [%Reason{capability: {:unsupported_instance_script, "instance_other"}}]} =
               Condition.evaluate(instance_context({:unsupported_script, "instance_other"}), condition)

      assert {:unknown, [%Reason{capability: :missing_instance_copy}]} =
               Condition.evaluate(instance_context(:missing_copy), condition)

      assert {:unknown, [%Reason{capability: {:missing_fact, :world, :instance_data}}]} =
               Condition.evaluate(Context.new(), condition)
    end

    test "invalid comparison and reversed unknown remain unknown" do
      condition = %{instance_condition(0, 9) | reverse?: true}

      assert {:unknown, [%Reason{capability: :invalid_comparison}]} =
               Condition.evaluate(instance_context(%{7 => {:ok, 0}}), condition)

      unsupported = %{instance_condition(0, 0) | reverse?: true}

      assert {:unknown, [%Reason{capability: {:unsupported_instance_field, 7}}]} =
               Condition.evaluate(
                 instance_context(%{7 => {:error, {:unsupported_field, 7}}}),
                 unsupported
               )
    end

    test "composes instance results with three-valued AND and OR" do
      met = instance_condition(2, 0)
      unknown = %{instance_condition(0, 0) | value1: 5}
      context = instance_context(%{7 => {:ok, 2}, 5 => {:error, {:unsupported_field, 5}}})

      assert {:unknown, _reasons} = Condition.evaluate(context, %Condition{type: :and, children: [met, unknown]})
      assert Condition.evaluate(context, %Condition{type: :or, children: [met, unknown]}) == :met
    end
  end

  defp assert_combinations(type, combinations) do
    Enum.each(combinations, fn {values, expected} ->
      tree = %Condition{type: type, children: Enum.map(values, &leaf/1)}
      result = Condition.evaluate(context(), tree)

      if expected == :unknown do
        assert match?({:unknown, _reasons}, result)
      else
        assert result == expected
      end
    end)
  end

  defp leaf(:met), do: %Condition{type: :source_entry, value1: 38}
  defp leaf(:unmet), do: %Condition{type: :source_entry, value1: 39}
  defp leaf(:unknown), do: %Condition{entry: 5, type: :level}

  defp context, do: Context.new(source: Subject.new(entry: 38))

  defp spawn_context(db_guid),
    do: Context.new(source: Subject.new(kind: :creature, db_guid: db_guid), content_patch: 10)

  defp db_guid(guids) do
    [value1, value2, value3, value4] = Enum.take(guids ++ [0, 0, 0, 0], 4)
    %Condition{type: :db_guid, value1: value1, value2: value2, value3: value3, value4: value4}
  end

  defp instance_condition(expected, comparison) do
    %Condition{entry: 3_755, type: :instance_data, value1: 7, value2: expected, value3: comparison}
  end

  defp instance_context(fields) when is_map(fields) do
    snapshot = %Snapshot{
      world: WorldRef.instance(329, 1),
      status: :available,
      script_name: "instance_stratholme",
      fields: fields
    }

    Context.new(world: %{instance_data: snapshot})
  end

  defp instance_context(status) do
    snapshot = %Snapshot{world: WorldRef.instance(329, 1), status: status}
    Context.new(world: %{instance_data: snapshot})
  end
end
