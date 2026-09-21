defmodule ThistleTea.Game.Entity.Data.QuestDependencies do
  @moduledoc """
  Resolved quest relationships cached with each quest template. Related quest
  tuples contain the quest ID and whether its rewards are repeatable.
  """

  defstruct prerequisites: [],
            exclusive_quests: [],
            previous_chain_quests: [],
            next_chain_quest: nil,
            breadcrumb_targets: [],
            dependent_breadcrumb_quests: [],
            valid?: true

  defmodule Prerequisite do
    @moduledoc false
    @enforce_keys [:quest_id, :state, :group_quests]
    defstruct [:quest_id, :state, :group_quests]
  end
end
