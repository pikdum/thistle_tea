defmodule ThistleTea.Game.Entity.Logic.LootRoll do
  @moduledoc """
  Pure need/greed roll state for one blocked loot slot: tracks eligible
  voters, collects votes, and resolves a winner — need beats greed, missing
  votes count as pass.
  """
  defstruct [:slot, :item_id, :count, eligible: [], votes: %{}]

  def new(slot, item_id, count, eligible_guids) do
    %__MODULE__{slot: slot, item_id: item_id, count: count, eligible: eligible_guids}
  end

  def vote(%__MODULE__{} = roll, guid, vote) when vote in [:pass, :need, :greed] do
    if guid in roll.eligible and not Map.has_key?(roll.votes, guid) do
      {:ok, %{roll | votes: Map.put(roll.votes, guid, vote)}}
    else
      :error
    end
  end

  def vote(_roll, _guid, _vote), do: :error

  def complete?(%__MODULE__{} = roll) do
    Enum.all?(roll.eligible, &Map.has_key?(roll.votes, &1))
  end

  def resolve(%__MODULE__{} = roll, rand \\ fn -> :rand.uniform(100) end) do
    case {contenders(roll, :need), contenders(roll, :greed)} do
      {[], []} -> :all_passed
      {[], greedy} -> pick_winner(greedy, :greed, rand)
      {needy, _greedy} -> pick_winner(needy, :need, rand)
    end
  end

  defp contenders(%__MODULE__{votes: votes}, vote) do
    for {guid, ^vote} <- votes, do: guid
  end

  defp pick_winner(guids, vote, rand) do
    rolled = Enum.map(guids, fn guid -> {guid, rand.()} end)
    {winner, number} = Enum.max_by(rolled, fn {_guid, number} -> number end)
    {:won, winner, number, vote, rolled}
  end
end
