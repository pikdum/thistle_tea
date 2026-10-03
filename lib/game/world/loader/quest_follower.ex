defmodule ThistleTea.Game.World.Loader.QuestFollower do
  @moduledoc """
  Boot loader for the C++-scripted follower quests in
  `Core.Quest.QuestFollower.Catalog`. It lowers each follower into script
  steps with their broadcast texts resolved. Most are appended to the
  quest's own start script; a follower started from gossip becomes a gossip
  option on its creature instead. Runs after the quest and gossip loaders.
  """

  alias ThistleTea.Game.Core.Quest.QuestFollower
  alias ThistleTea.Game.Core.Quest.QuestFollower.Catalog
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Gossip.Option
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Script

  @close_gossip -1

  def load_all(followers \\ Catalog.all()) do
    {gossip, accept} = Enum.split_with(followers, &is_binary(&1.gossip))

    accept
    |> Map.new(fn %QuestFollower{} = follower -> {follower.quest_id, QuestFollower.start_steps(follower)} end)
    |> QuestLoader.append_start_steps()

    Enum.each(gossip, &GossipLoader.add_creature_option(&1.entry, gossip_option(&1)))
  end

  def gossip_option(%QuestFollower{} = follower, resolve_texts \\ &Script.resolve_texts/1) do
    %Option{
      icon: 0,
      text: follower.gossip,
      option_id: GossipLoader.option_gossip(),
      npc_flag: 0,
      action_menu_id: @close_gossip,
      talk_credit?: false,
      condition: QuestFollower.gossip_condition(follower),
      action_steps: follower |> QuestFollower.start_steps() |> resolve_texts.()
    }
  end
end
