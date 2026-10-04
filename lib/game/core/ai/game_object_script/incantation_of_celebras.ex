defmodule ThistleTea.Game.Core.AI.GameObjectScript.IncantationOfCelebras do
  @moduledoc """
  vmangos `go_book_celebras`, the tome Celebras the Redeemed sets out in
  Maraudon during The Scepter of Celebras (7046). A player on the quest who
  reads it speaks the incantation: the tome vanishes and Celebras, waiting
  at his altar (`QuestEscort.Catalog`), goes on with the ritual.
  """

  @behaviour ThistleTea.Game.Core.AI.GameObjectScript

  alias ThistleTea.Game.Core.AI.GameObjectScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @incantation 178_965
  @celebras_the_redeemed 13_716
  @scepter_of_celebras 7_046
  @incomplete 1
  @altar_reach 40
  @read_script 1

  @impl GameObjectScript
  def entries, do: [@incantation]

  @impl GameObjectScript
  def steps(@incantation, _position) do
    [
      %ScriptStep{
        command: :start_script,
        datalong: @read_script,
        dataint: 100,
        sub_scripts: %{@read_script => read()},
        condition: %Condition{
          type: :quest_taken,
          value1: @scepter_of_celebras,
          value2: @incomplete,
          swap_targets?: true
        }
      }
    ]
  end

  defp read do
    [
      %ScriptStep{
        command: :release_waypoints,
        target_type: :nearest_creature_with_entry,
        target_param1: @celebras_the_redeemed,
        target_param2: @altar_reach,
        swap_final?: true
      },
      %ScriptStep{command: :remove_object, swap_final?: true}
    ]
  end
end
