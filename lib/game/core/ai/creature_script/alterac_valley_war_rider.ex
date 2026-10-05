defmodule ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyWarRider do
  @moduledoc "Alterac Valley's named flying attackers, their enemy-base approach, patrol and ranged combat."

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Combat
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @horde [14_943, 14_944, 14_945]
  @alliance [14_946, 14_947, 14_948]
  @point_motion 9
  @arrival 1

  @impl true
  def entries, do: @horde ++ @alliance

  @impl true
  def events(entry) do
    [
      CreatureScript.event(entry, 1, :spawned, depart(entry)),
      CreatureScript.event(entry, 2, :movement_inform, [phase(1), reaction(2)],
        param1: @point_motion,
        param2: @arrival
      ),
      CreatureScript.event(entry, 3, :ooc_los, [%ScriptStep{command: :attack_start}],
        param1: 1,
        param2: 50,
        param3: 1_000,
        param4: 1_000,
        inverse_phase_mask: CreatureScript.only_in_phases([1])
      ),
      Combat.every(entry, 4, Combat.cast(22_088), 0, 5_000, condition: within(30)),
      Combat.every(entry, 5, Combat.cast(15_285), 8_000, 7_500, condition: within(30)),
      Combat.every(entry, 6, Combat.cast(21_188), 13_000, 9_000, condition: within(30))
    ]
  end

  defp depart(entry) do
    position = if entry in @horde, do: {618.4, -87.97, 85.77, 0.0}, else: {-1311.53, -355.28, 130.93, 0.0}

    [
      %ScriptStep{command: :set_fly, datalong: 1},
      %ScriptStep{command: :set_run, datalong: 1},
      %ScriptStep{command: :set_caster_chase_distance, datalong: 25},
      %ScriptStep{command: :set_home_position, position: position},
      %ScriptStep{command: :set_default_movement, datalong: 1, datalong3: 55},
      reaction(0),
      %ScriptStep{command: :move_to, position: position, datalong3: 13, datalong4: 2, dataint: @arrival}
    ]
  end

  defp phase(phase), do: %ScriptStep{command: :set_phase, datalong: phase}
  defp reaction(mode), do: %ScriptStep{command: :set_react_state, datalong: mode}
  defp within(yards), do: %Condition{type: :distance_to_target, value1: yards, value2: 2}
end
