defmodule ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyCavalry do
  @moduledoc "Alterac cavalry commanders, eight-rider formations, combat dismounting, and surviving rider lifetimes."

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Combat
  alias ThistleTea.Game.Core.AI.CreatureScript.Route
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @commanders %{13_441 => {13_440, 1_166, 2, 81, 8_890, 8_891}, 13_577 => {13_576, 2_786, 5, 92, 8_906, 8_908}}
  @formation_flags 0x87
  @rally_script 1

  @impl true
  def entries, do: [13_440, 13_441, 13_576, 13_577]

  @impl true
  def events(entry) when is_map_key(@commanders, entry) do
    {_rider, mount, _rally, _last, _speech, _warcry} = Map.fetch!(@commanders, entry)

    [
      CreatureScript.event(entry, 1, :spawned, [mount(mount), home(), notify(0)]),
      CreatureScript.event(entry, 2, :aggro, [mount(0)]),
      CreatureScript.event(entry, 3, :evade, [mount(mount), run()]),
      CreatureScript.event(entry, 4, :death, [notify(1)]),
      CreatureScript.event(entry, 5, :script_event, launch(entry),
        param1: 1,
        inverse_phase_mask: CreatureScript.only_in_phases([0])
      )
    ]
  end

  def events(entry) do
    commander = if entry == 13_440, do: 13_441, else: 13_577
    {_rider, display, _rally, _last, _speech, _warcry} = Map.fetch!(@commanders, commander)

    [
      CreatureScript.event(entry, 1, :spawned, [mount(display), run(), join(commander, 0x80)]),
      CreatureScript.event(entry, 2, :aggro, [mount(0)]),
      CreatureScript.event(entry, 3, :evade, [mount(display), run()]),
      CreatureScript.event(entry, 4, :group_member_died, orphan(),
        param1: commander,
        param2: 1,
        inverse_phase_mask: CreatureScript.only_in_phases([0])
      ),
      CreatureScript.event(entry, 5, :group_member_died, survivor(),
        param1: commander,
        param2: 1,
        inverse_phase_mask: CreatureScript.only_in_phases([2])
      ),
      CreatureScript.event(entry, 6, :spawned, orphan(),
        condition: %Condition{
          type: :nearby_creature,
          value1: commander,
          value2: 100,
          swap_targets?: true,
          reverse?: true
        },
        inverse_phase_mask: CreatureScript.only_in_phases([0])
      )
    ]
  end

  @impl true
  def routes do
    commanders =
      Enum.map(@commanders, fn {entry, {rider, _mount, rally, last, speech, warcry}} ->
        %Route{entry: entry, points: %{rally => rally(rider, entry, speech, warcry), last => [home(), stop()]}}
      end)

    commanders ++ [%Route{entry: 13_440}, %Route{entry: 13_576}]
  end

  defp launch(entry) do
    {rider, _mount, _rally, _last, _speech, _warcry} = Map.fetch!(@commanders, entry)

    [phase(1), flags(0x101, 2), flags(0x1000, 1), run()] ++
      Enum.map(positions(entry), &summon(rider, &1)) ++
      [%ScriptStep{command: :start_waypoints, datalong: 5}]
  end

  defp positions(13_441) do
    for index <- 0..7 do
      {x, y, orientation} = if index < 4, do: {-1_230.0, -611.0, 5.4}, else: {-1_223.0, -619.0, 2.22}
      {x - 4 * rem(index, 5), y - 3 * rem(index, 5), 54.0, orientation}
    end
  end

  defp positions(13_577) do
    for index <- 0..7 do
      {x, y} = if index < 4, do: {610.0, -35.0}, else: {607.0, -37.0}
      {x + 2 * rem(index, 5), y - 3 * rem(index, 5), 45.0, 0.6}
    end
  end

  defp summon(entry, position) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: 10_000,
      dataint3: -1,
      dataint4: 5,
      position: position
    }
  end

  defp rally(rider, commander, speech, warcry) do
    call = %ScriptStep{
      command: :start_script_for_all,
      datalong: @rally_script,
      datalong2: 2,
      datalong3: rider,
      datalong4: if(commander == 13_441, do: 50, else: 20),
      sub_scripts: %{
        @rally_script => [
          Combat.talk(warcry),
          run(),
          phase(2),
          %ScriptStep{command: :leave_creature_group},
          join(commander, @formation_flags)
        ]
      }
    }

    [
      Combat.talk(speech),
      %ScriptStep{
        command: :hold_waypoints,
        datalong: 6_000,
        datalong2: 1,
        sub_scripts: %{@rally_script => [call]}
      }
    ]
  end

  defp join(commander, flags) do
    %ScriptStep{
      command: :join_creature_group,
      datalong: flags,
      formation_from_position?: true,
      target_type: :nearest_creature_with_entry,
      target_param1: commander,
      target_param2: 100
    }
  end

  defp orphan, do: [%ScriptStep{command: :start_waypoints, datalong: 5} | survivor()]
  defp survivor, do: [phase(1), %ScriptStep{command: :despawn, datalong: 600_000}]

  defp mount(display), do: %ScriptStep{command: :mount, datalong: display, datalong2: 1}
  defp phase(phase), do: %ScriptStep{command: :set_phase, datalong: phase}
  defp flags(value, mode), do: %ScriptStep{command: :modify_flags, datalong: 46, datalong2: value, datalong3: mode}
  defp run, do: %ScriptStep{command: :set_run, datalong: 1}
  defp home, do: %ScriptStep{command: :set_home_position, datalong: 1}
  defp stop, do: %ScriptStep{command: :movement, datalong: 0}
  defp notify(event), do: %ScriptStep{command: :battleground_event, datalong: event}
end
