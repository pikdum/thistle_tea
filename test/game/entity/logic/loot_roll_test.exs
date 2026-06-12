defmodule ThistleTea.Game.Entity.Logic.LootRollTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.LootRoll

  defp roll_with_votes(votes) do
    roll = LootRoll.new(0, 1234, 1, Enum.map(votes, &elem(&1, 0)))

    Enum.reduce(votes, roll, fn {guid, vote}, roll ->
      {:ok, roll} = LootRoll.vote(roll, guid, vote)
      roll
    end)
  end

  describe "vote/3" do
    test "records eligible votes" do
      roll = LootRoll.new(0, 1234, 1, [1, 2])
      assert {:ok, roll} = LootRoll.vote(roll, 1, :need)
      assert roll.votes == %{1 => :need}
    end

    test "rejects ineligible voters" do
      roll = LootRoll.new(0, 1234, 1, [1, 2])
      assert :error = LootRoll.vote(roll, 99, :need)
    end

    test "rejects double votes" do
      roll = LootRoll.new(0, 1234, 1, [1, 2])
      {:ok, roll} = LootRoll.vote(roll, 1, :need)
      assert :error = LootRoll.vote(roll, 1, :greed)
    end
  end

  describe "complete?/1" do
    test "is true once all eligible members voted" do
      roll = LootRoll.new(0, 1234, 1, [1, 2])
      refute LootRoll.complete?(roll)

      {:ok, roll} = LootRoll.vote(roll, 1, :pass)
      refute LootRoll.complete?(roll)

      {:ok, roll} = LootRoll.vote(roll, 2, :greed)
      assert LootRoll.complete?(roll)
    end
  end

  describe "resolve/2" do
    test "need beats greed" do
      roll = roll_with_votes([{1, :greed}, {2, :need}])
      assert {:won, 2, _number, :need, [{2, _}]} = LootRoll.resolve(roll)
    end

    test "highest roll among contenders wins" do
      roll = roll_with_votes([{1, :need}, {2, :need}])
      numbers = Stream.cycle([10, 90])
      {:ok, agent} = Agent.start_link(fn -> numbers end)

      rand = fn ->
        Agent.get_and_update(agent, fn stream ->
          {Enum.at(stream, 0), Stream.drop(stream, 1)}
        end)
      end

      assert {:won, 2, 90, :need, rolled} = LootRoll.resolve(roll, rand)
      assert Enum.sort(rolled) == [{1, 10}, {2, 90}]
    end

    test "greed wins when nobody needs" do
      roll = roll_with_votes([{1, :pass}, {2, :greed}])
      assert {:won, 2, _number, :greed, _rolled} = LootRoll.resolve(roll)
    end

    test "all passed when nobody rolls" do
      roll = roll_with_votes([{1, :pass}, {2, :pass}])
      assert LootRoll.resolve(roll) == :all_passed
    end

    test "missing votes count as pass" do
      roll = LootRoll.new(0, 1234, 1, [1, 2])
      assert LootRoll.resolve(roll) == :all_passed
    end
  end
end
