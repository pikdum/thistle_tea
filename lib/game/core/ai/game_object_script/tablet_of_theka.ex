defmodule ThistleTea.Game.Core.AI.GameObjectScript.TabletOfTheka do
  @moduledoc """
  vmangos `go_table_theka`: reading the Tablet of Theka in Zul'Farrak during
  The Spider God (2936) teaches the player the name of the troll spider god.
  That completes the quest.
  """

  @behaviour ThistleTea.Game.Core.AI.GameObjectScript

  alias ThistleTea.Game.Core.AI.GameObjectScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @tablet 142_715
  @the_spider_god 2_936
  @incomplete 1

  @impl GameObjectScript
  def entries, do: [@tablet]

  @impl GameObjectScript
  def steps(@tablet, _position) do
    [
      %ScriptStep{
        command: :quest_explored,
        datalong: @the_spider_god,
        condition: %Condition{type: :quest_taken, value1: @the_spider_god, value2: @incomplete, swap_targets?: true}
      }
    ]
  end
end
