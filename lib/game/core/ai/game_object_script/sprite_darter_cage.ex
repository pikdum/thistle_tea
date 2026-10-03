defmodule ThistleTea.Game.Core.AI.GameObjectScript.SpriteDarterCage do
  @moduledoc """
  The cage door in the Grimtotem camp in Feralas, for vmangos
  `npc_captured_sprite_darter`, which waits for it to open during Freedom for
  All Creatures (2969). A player on the quest unlocking it with the Bamboo
  Cage Key frees every captured sprite darter in the pen, and each runs off
  along an escape route (`CreatureScript.KindalMoonweaver`).
  """

  @behaviour ThistleTea.Game.Core.AI.GameObjectScript

  alias ThistleTea.Game.Core.AI.CreatureScript.KindalMoonweaver
  alias ThistleTea.Game.Core.AI.GameObjectScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @cage_door 143_979
  @sprite_darter 7_997
  @freedom_for_all_creatures 2_969
  @incomplete 1
  @creatures 2
  @pen_radius 45
  @escape_script 1

  @impl GameObjectScript
  def entries, do: [@cage_door]

  @impl GameObjectScript
  def steps(@cage_door, _position) do
    [
      %ScriptStep{
        command: :start_script_for_all,
        datalong: @escape_script,
        datalong2: @creatures,
        datalong3: @sprite_darter,
        datalong4: @pen_radius,
        sub_scripts: %{@escape_script => KindalMoonweaver.escape_steps()},
        condition: %Condition{
          type: :quest_taken,
          value1: @freedom_for_all_creatures,
          value2: @incomplete,
          swap_targets?: true
        }
      }
    ]
  end
end
