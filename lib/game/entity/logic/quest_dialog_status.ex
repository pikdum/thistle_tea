defmodule ThistleTea.Game.Entity.Logic.QuestDialogStatus do
  alias ThistleTea.Game.Entity.Data.Quest

  @none 0
  @unavailable 1
  @chat 2
  @incomplete 3
  @reward_rep 4
  @available 5
  @reward 7

  def none, do: @none
  def unavailable, do: @unavailable
  def chat, do: @chat
  def incomplete, do: @incomplete
  def reward_rep, do: @reward_rep
  def available, do: @available
  def reward, do: @reward

  def for_giver(giver_quests, player_level) do
    giver_quests
    |> Enum.map(&giver_status(&1, player_level))
    |> Enum.max(fn -> @none end)
  end

  defp giver_status(%Quest{min_level: min_level}, player_level) when player_level >= min_level, do: @available

  defp giver_status(%Quest{}, _player_level), do: @unavailable
end
