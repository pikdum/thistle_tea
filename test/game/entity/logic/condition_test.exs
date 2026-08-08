defmodule ThistleTea.Game.Entity.Logic.ConditionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Logic.Condition, as: Evaluator
  alias ThistleTea.Game.Entity.Logic.Condition.Context
  alias ThistleTea.Game.Entity.Logic.Condition.InstanceDataSnapshot, as: Snapshot
  alias ThistleTea.Game.Entity.Logic.Condition.Reason
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.WorldRef

  describe "evaluate/2" do
    test "nil and none are met" do
      context = Context.new()

      assert Evaluator.evaluate(context, nil) == :met
      assert Evaluator.evaluate(context, %Condition{type: :none}) == :met
    end

    test "source entry and db guid match any nonzero raw value" do
      context = Context.new(source: Subject.new(entry: 38, db_guid: 80_152))

      assert Evaluator.evaluate(context, %Condition{type: :source_entry, value1: 38}) == :met
      assert Evaluator.evaluate(context, %Condition{type: :source_entry, value1: 1, value3: 38}) == :met
      assert Evaluator.evaluate(context, %Condition{type: :source_entry, value1: 39}) == :unmet
      assert Evaluator.evaluate(context, %Condition{type: :db_guid, value1: 1, value2: 80_152}) == :met
    end

    test "missing facts are explicit unknown reasons" do
      condition = %Condition{entry: 42, type: :db_guid, value1: 80_152}

      assert {:unknown, [%Reason{entry: 42, type: :db_guid, capability: {:missing_fact, :source, :db_guid}}]} =
               Evaluator.evaluate(Context.new(source: Subject.new()), condition)
    end

    test "precomputed boundary facts preserve explicit unknown results" do
      condition = %Condition{entry: 42, type: :nearby_creature}
      unknown = {:unknown, [%Reason{entry: 42, type: :nearby_creature, capability: :position}]}
      context = Context.new(environment: %{condition_results: %{42 => unknown}})

      assert Evaluator.evaluate(context, condition) == unknown
    end

    test "precomputed boundary facts keep structurally distinct unresolved entries" do
      first = %Condition{type: :nearby_creature, value1: 1}
      second = %Condition{type: :nearby_creature, value1: 2}

      context =
        Context.new(environment: %{condition_results: %{first => :met, second => :unmet}})

      assert Evaluator.evaluate(context, first) == :met
      assert Evaluator.evaluate(context, second) == :unmet
    end

    test "reputation bounds use the projected rank" do
      context = Context.new(target: Subject.new(reputation_ranks: %{529 => :honored}))

      assert Evaluator.evaluate(context, %Condition{type: :reputation_rank_min, value1: 529, value2: 5}) == :met
      assert Evaluator.evaluate(context, %Condition{type: :reputation_rank_min, value1: 529, value2: 6}) == :unmet
      assert Evaluator.evaluate(context, %Condition{type: :reputation_rank_max, value1: 529, value2: 5}) == :met
    end

    test "target swapping happens before a tree is evaluated" do
      context = Context.new(source: Subject.new(entry: 38), target: Subject.new(entry: 39))

      assert Evaluator.evaluate(context, %Condition{type: :source_entry, value1: 39, swap_targets?: true}) == :met

      tree = %Condition{
        type: :and,
        swap_targets?: true,
        children: [%Condition{type: :source_entry, value1: 39}]
      }

      assert Evaluator.evaluate(context, tree) == :met
    end

    test "reverse negates met and unmet but preserves unknown" do
      context = Context.new(source: Subject.new(entry: 38))

      assert Evaluator.evaluate(context, %Condition{type: :source_entry, value1: 38, reverse?: true}) == :unmet
      assert Evaluator.evaluate(context, %Condition{type: :source_entry, value1: 39, reverse?: true}) == :met

      assert {:unknown, [%Reason{capability: {:missing_fact, :target, :level}}]} =
               Evaluator.evaluate(context, %Condition{type: :level, reverse?: true})
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

      assert {:unknown, _reasons} = Evaluator.evaluate(context(), tree)
    end

    test "unresolved and unknown upstream types stay unknown" do
      assert {:unknown, [%Reason{capability: :unresolved_tree}]} =
               Evaluator.evaluate(context(), Condition.unresolved(10))

      assert {:unknown, [%Reason{capability: {:unsupported_condition_type, 99}}]} =
               Evaluator.evaluate(context(), %Condition{type: {:unsupported, 99}})
    end
  end

  describe "compare/3" do
    test "implements VMangos comparison modes" do
      assert Evaluator.compare(5, 5, 0)
      assert Evaluator.compare(5, 4, 1)
      assert Evaluator.compare(5, 6, 2)
      refute Evaluator.compare(5, 4, 0)
      refute Evaluator.compare(5, 6, 1)
      refute Evaluator.compare(5, 4, 2)
      assert Evaluator.compare(5, 5, 3) == {:error, :invalid_comparison}
    end
  end

  describe "instance_data" do
    test "evaluates equality and ordered comparisons from a supplied snapshot" do
      context = instance_context(%{7 => {:ok, 2}})

      assert Evaluator.evaluate(context, instance_condition(2, 0)) == :met
      assert Evaluator.evaluate(context, instance_condition(1, 0)) == :unmet
      assert Evaluator.evaluate(context, instance_condition(1, 1)) == :met
      assert Evaluator.evaluate(context, instance_condition(3, 1)) == :unmet
      assert Evaluator.evaluate(context, instance_condition(3, 2)) == :met
      assert Evaluator.evaluate(context, instance_condition(1, 2)) == :unmet
    end

    test "compares an unwritten registered field as zero" do
      assert Evaluator.evaluate(instance_context(%{7 => {:ok, 0}}), instance_condition(0, 0)) == :met
    end

    test "treats definitive absence as unmet" do
      condition = instance_condition(0, 0)

      assert Evaluator.evaluate(instance_context(:no_instance_script), condition) == :unmet
      assert Evaluator.evaluate(instance_context(:open_world), condition) == :unmet
    end

    test "keeps unsupported and missing capabilities structured unknowns" do
      condition = instance_condition(0, 0)

      assert {:unknown, [%Reason{capability: {:unsupported_instance_field, 7}}]} =
               Evaluator.evaluate(instance_context(%{7 => {:error, {:unsupported_field, 7}}}), condition)

      assert {:unknown, [%Reason{capability: {:unsupported_instance_script, "instance_other"}}]} =
               Evaluator.evaluate(instance_context({:unsupported_script, "instance_other"}), condition)

      assert {:unknown, [%Reason{capability: :missing_instance_copy}]} =
               Evaluator.evaluate(instance_context(:missing_copy), condition)

      assert {:unknown, [%Reason{capability: {:missing_fact, :world, :instance_data}}]} =
               Evaluator.evaluate(Context.new(), condition)
    end

    test "invalid comparison and reversed unknown remain unknown" do
      condition = %{instance_condition(0, 9) | reverse?: true}

      assert {:unknown, [%Reason{capability: :invalid_comparison}]} =
               Evaluator.evaluate(instance_context(%{7 => {:ok, 0}}), condition)

      unsupported = %{instance_condition(0, 0) | reverse?: true}

      assert {:unknown, [%Reason{capability: {:unsupported_instance_field, 7}}]} =
               Evaluator.evaluate(
                 instance_context(%{7 => {:error, {:unsupported_field, 7}}}),
                 unsupported
               )
    end

    test "composes instance results with three-valued AND and OR" do
      met = instance_condition(2, 0)
      unknown = %{instance_condition(0, 0) | value1: 5}
      context = instance_context(%{7 => {:ok, 2}, 5 => {:error, {:unsupported_field, 5}}})

      assert {:unknown, _reasons} = Evaluator.evaluate(context, %Condition{type: :and, children: [met, unknown]})
      assert Evaluator.evaluate(context, %Condition{type: :or, children: [met, unknown]}) == :met
    end
  end

  defp assert_combinations(type, combinations) do
    Enum.each(combinations, fn {values, expected} ->
      tree = %Condition{type: type, children: Enum.map(values, &leaf/1)}
      result = Evaluator.evaluate(context(), tree)

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
