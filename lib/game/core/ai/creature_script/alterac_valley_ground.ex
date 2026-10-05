defmodule ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyGround do
  @moduledoc "Quartermaster deployments and armored infantry escorts with authored rally and assault routes."

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Combat
  alias ThistleTea.Game.Core.AI.CreatureScript.Route
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @commanders %{13_446 => {13_524, 48, 8_906, 8_908}, 13_449 => {13_528, 53, 8_890, 8_891}}
  @troops Enum.to_list(13_524..13_531)
  @rally_script 1

  @impl true
  def entries, do: [12_096, 12_097, 13_446, 13_449] ++ @troops

  @impl true
  def summon_entries, do: [13_446, 13_449] ++ @troops

  @impl true
  def events(entry) when entry in [12_096, 12_097] do
    [
      CreatureScript.event(entry, 1, :spawned, [notify(0)]),
      CreatureScript.event(entry, 2, :death, [notify(1)])
    ]
  end

  def events(entry) when is_map_key(@commanders, entry) do
    [
      CreatureScript.event(entry, 1, :spawned, [home(), notify(3)]),
      CreatureScript.event(entry, 2, :death, [notify(2)]),
      CreatureScript.event(entry, 3, :script_event, launch(),
        param1: 1,
        inverse_phase_mask: CreatureScript.only_in_phases([0])
      )
    ]
  end

  def events(entry) do
    commander = commander(entry)

    [
      CreatureScript.event(entry, 1, :spawned, [run(), join(commander, 0x80)]),
      CreatureScript.event(entry, 2, :evade, [run()]),
      CreatureScript.event(entry, 3, :group_member_died, orphan(),
        param1: commander,
        param2: 1,
        inverse_phase_mask: CreatureScript.only_in_phases([0])
      ),
      CreatureScript.event(entry, 4, :group_member_died, [phase(1), run()],
        param1: commander,
        param2: 1,
        inverse_phase_mask: CreatureScript.only_in_phases([2])
      ),
      CreatureScript.event(entry, 5, :spawned, orphan(),
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
      Enum.map(@commanders, fn {entry, {base, last, speech, warcry}} ->
        %Route{entry: entry, points: %{2 => rally(entry, base, speech, warcry), last => [home(), stop()]}}
      end)

    commanders ++ Enum.map(@troops, &%Route{entry: &1, points: %{last_point(&1) => [home(), stop()]}})
  end

  def assembly(team, tier) when team in [:alliance, :horde] and tier in 0..3 do
    {commander, base, position, announcement} =
      if team == :alliance,
        do: {13_446, 13_524, {-243.75, -431.32, 20.0, 2.59}, 8_907},
        else: {13_449, 13_528, {-470.38, -51.84, 41.0, 5.93}, 8_913}

    [Combat.talk(announcement), %ScriptStep{command: :emote, datalong: 22}, summon(commander, position)] ++
      Enum.map(positions(team), &summon(base + tier, &1))
  end

  defp positions(:alliance) do
    for index <- 0..9 do
      {x, y} = if index < 5, do: {-240.9, -431.11}, else: {-238.35, -432.42}
      {x - rem(index, 5), y - rem(index, 5), 20.2, 2.59}
    end
  end

  defp positions(:horde) do
    for index <- 0..9 do
      {x, y} = if index < 5, do: {-472.2, -48.4}, else: {-474.8, -48.7}
      {x - 0.4 * rem(index, 5), y - 1.6 * rem(index, 5), 41.3, 5.93}
    end
  end

  defp launch do
    [
      phase(1),
      %ScriptStep{command: :emote, datalong: 22},
      flags(0x101, 2),
      flags(0x1000, 1),
      %ScriptStep{command: :set_run, datalong: 0},
      %ScriptStep{command: :start_waypoints, datalong: 5}
    ]
  end

  defp rally(commander, base, speech, warcry) do
    calls = Enum.map(base..(base + 3), &rally_troops(&1, commander, warcry))

    [
      Combat.talk(speech),
      %ScriptStep{
        command: :hold_waypoints,
        datalong: 6_000,
        datalong2: @rally_script,
        sub_scripts: %{@rally_script => [run() | calls]}
      }
    ]
  end

  defp rally_troops(entry, commander, warcry) do
    %ScriptStep{
      command: :start_script_for_all,
      datalong: @rally_script,
      datalong2: 2,
      datalong3: entry,
      datalong4: 40,
      sub_scripts: %{
        @rally_script => [
          Combat.talk(warcry),
          run(),
          phase(2),
          %ScriptStep{command: :leave_creature_group},
          join(commander, 0x87)
        ]
      }
    }
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

  defp commander(entry) when entry < 13_528, do: 13_446
  defp commander(_entry), do: 13_449
  defp last_point(entry) when entry < 13_528, do: 49
  defp last_point(_entry), do: 54
  defp orphan, do: [phase(1), run(), %ScriptStep{command: :start_waypoints, datalong: 5}]
  defp phase(phase), do: %ScriptStep{command: :set_phase, datalong: phase}
  defp flags(value, mode), do: %ScriptStep{command: :modify_flags, datalong: 46, datalong2: value, datalong3: mode}
  defp run, do: %ScriptStep{command: :set_run, datalong: 1}
  defp home, do: %ScriptStep{command: :set_home_position, datalong: 1}
  defp stop, do: %ScriptStep{command: :movement, datalong: 0}
  defp notify(event), do: %ScriptStep{command: :battleground_event, datalong: event}
end
