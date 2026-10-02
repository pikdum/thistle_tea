defmodule ThistleTea.Game.World.Loader.QuestFollower do
  @moduledoc """
  Boot loader for the C++-scripted follower quests in
  `Core.Quest.QuestFollower.Catalog`. It lowers each follower into script
  steps, resolves their broadcast texts, and appends them to the quest's own
  start script. Runs after the quest loader.
  """

  alias ThistleTea.Game.Core.Quest.QuestFollower
  alias ThistleTea.Game.Core.Quest.QuestFollower.Catalog
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader

  def load_all(followers \\ Catalog.all()) do
    followers
    |> Map.new(fn %QuestFollower{} = follower -> {follower.quest_id, QuestFollower.start_steps(follower)} end)
    |> QuestLoader.append_start_steps()
  end
end
