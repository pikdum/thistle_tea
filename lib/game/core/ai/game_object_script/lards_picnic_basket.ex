defmodule ThistleTea.Game.Core.AI.GameObjectScript.LardsPicnicBasket do
  @moduledoc """
  vmangos `go_lards_picnic_basket`: opening Lard's Picnic Basket in the
  Hinterlands springs three Vilebranch Kidnappers on the player, one of whom
  carries Lard's Lunch for Lard Lost His Lunch (7840). They leave thirty
  seconds later unless killed first.

  vmangos keeps the basket closed for five minutes after the ambush. Here it
  stays quiet only while kidnappers are still about it.
  """

  @behaviour ThistleTea.Game.Core.AI.GameObjectScript

  alias ThistleTea.Game.Core.AI.GameObjectScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @basket 179_910
  @kidnapper 14_748
  @kidnappers 3
  @despawn_ms 30_000
  @attack_user 8
  @timed_or_dead_despawn 1
  @ambush_script 1
  @lookout_radius 40

  @impl GameObjectScript
  def entries, do: [@basket]

  @impl GameObjectScript
  def steps(@basket, _position) do
    [
      %ScriptStep{
        command: :start_script,
        datalong: @ambush_script,
        dataint: 100,
        sub_scripts: %{@ambush_script => List.duplicate(kidnapper(), @kidnappers)},
        condition: %Condition{type: :nearby_creature, value1: @kidnapper, value2: @lookout_radius, reverse?: true}
      }
    ]
  end

  defp kidnapper do
    %ScriptStep{
      command: :summon_creature,
      datalong: @kidnapper,
      datalong2: @despawn_ms,
      dataint3: @attack_user,
      dataint4: @timed_or_dead_despawn
    }
  end
end
