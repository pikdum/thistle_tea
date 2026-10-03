defmodule ThistleTea.Game.Core.AI.GameObjectScript.PantherCage do
  @moduledoc """
  vmangos `go_panther_cage`: unlocking the Panther Cage in Thousand Needles
  with the Panther Cage Key during Hypercapacitor Gizmo (5151) lets the
  Enraged Panther out at the player who opened it. The caged panther cannot
  be attacked until it is released.

  The player who opened the cage checks their own quest before the panther
  is told to attack, since the panther cannot read a player's quest log.
  """

  @behaviour ThistleTea.Game.Core.AI.GameObjectScript

  alias ThistleTea.Game.Core.AI.GameObjectScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @panther_cage 176_195
  @enraged_panther 10_992
  @hypercapacitor_gizmo 5151
  @incomplete 1
  @unit_flags 46
  @spawning_and_not_attackable 0x102
  @remove_flags 2
  @cage_reach 10
  @release_script 1

  @impl GameObjectScript
  def entries, do: [@panther_cage]

  @impl GameObjectScript
  def steps(@panther_cage, _position) do
    [
      %ScriptStep{
        command: :start_script,
        datalong: @release_script,
        dataint: 100,
        sub_scripts: %{@release_script => release()},
        condition: %Condition{
          type: :quest_taken,
          value1: @hypercapacitor_gizmo,
          value2: @incomplete,
          swap_targets?: true
        }
      }
    ]
  end

  defp release do
    Enum.map(
      [
        %ScriptStep{
          command: :modify_flags,
          datalong: @unit_flags,
          datalong2: @spawning_and_not_attackable,
          datalong3: @remove_flags
        },
        %ScriptStep{command: :attack_start}
      ],
      &%{
        &1
        | target_type: :nearest_creature_with_entry,
          target_param1: @enraged_panther,
          target_param2: @cage_reach,
          swap_final?: true
      }
    )
  end
end
