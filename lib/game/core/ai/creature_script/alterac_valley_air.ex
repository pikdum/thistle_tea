defmodule ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyAir do
  @moduledoc "Alterac Valley's six imprisoned wing commanders and their return to the faction base."

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Route
  alias ThistleTea.Game.Core.AI.ScriptStep

  @destinations %{13_179 => 74, 13_180 => 84, 13_181 => 97, 13_438 => 66, 13_439 => 76, 13_437 => 92}

  @impl true
  def entries, do: Map.keys(@destinations)

  @impl true
  def events(entry) do
    [
      CreatureScript.event(entry, 1, :spawned, prisoner(entry)),
      CreatureScript.event(entry, 2, :death, [notify(0)]),
      CreatureScript.event(entry, 3, :script_event, depart(entry),
        param1: 1,
        inverse_phase_mask: CreatureScript.only_in_phases([0])
      )
    ]
  end

  @impl true
  def routes do
    Enum.map(@destinations, fn {entry, point} ->
      %Route{entry: entry, points: %{point => arrived()}}
    end)
  end

  defp prisoner(entry) do
    stand = if entry in [13_439, 13_437], do: 1, else: 0

    [
      %ScriptStep{command: :set_home_position, datalong: 1},
      %ScriptStep{command: :stand_state, datalong: stand},
      notify(0)
    ]
  end

  defp depart(entry) do
    heal = if entry == 13_439, do: [%ScriptStep{command: :cast_spell, datalong: 5_759, target_self?: true}], else: []

    [
      %ScriptStep{command: :set_phase, datalong: 1},
      flags(46, 0x101, 2),
      flags(46, 0x1000, 1),
      flags(147, 2, 2),
      flags(143, 0xFFFFFFFF, 2),
      %ScriptStep{command: :stand_state, datalong: 0},
      %ScriptStep{command: :set_run, datalong: 1}
    ] ++ heal ++ [%ScriptStep{command: :start_waypoints, datalong: 5}]
  end

  defp arrived do
    [
      %ScriptStep{command: :set_phase, datalong: 2},
      flags(147, 2, 1),
      %ScriptStep{command: :set_home_position, datalong: 1},
      %ScriptStep{command: :movement, datalong: 0},
      notify(1)
    ]
  end

  defp flags(field, value, mode),
    do: %ScriptStep{command: :modify_flags, datalong: field, datalong2: value, datalong3: mode}

  defp notify(event), do: %ScriptStep{command: :battleground_event, datalong: event}
end
