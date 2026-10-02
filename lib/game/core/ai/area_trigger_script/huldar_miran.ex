defmodule ThistleTea.Game.Core.AI.AreaTriggerScript.HuldarMiran do
  @moduledoc """
  vmangos `at_huldar_miran`: reaching Huldar and Miran's camp outside the
  Loch Modan excavation finishes Resupplying the Excavation (273) and springs
  the Dark Iron ambush on the delivery. Saean turns hostile and goes for
  Miran, and two Dark Iron Ambushers join him for twenty-five seconds.

  The ambush needs Huldar, Miran, and Saean alive at the camp and no
  ambusher already about. Like vmangos, the quest is credited first, and
  the ambush only springs for a player who arrived with it unfinished.
  """

  @behaviour ThistleTea.Game.Core.AI.AreaTriggerScript

  alias ThistleTea.Game.Core.AI.AreaTriggerScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @camp 171
  @resupplying_the_excavation 273
  @miran 1379
  @saean 1380
  @ambusher 1981
  @huldar 2057
  @dark_iron 54
  @restore_on_respawn 0x01
  @camp_radius 60
  @ambush_radius 100
  @ambush_ms 25_000
  @incomplete 1
  @ambush_script 1
  @nearest_creature 10
  @timed_or_dead_despawn 1

  @ambushers [
    {-5759.852051, -3441.279053, 305.573212, 2.174024},
    {-5757.629883, -3437.680908, 304.265106, 2.610265}
  ]

  @impl AreaTriggerScript
  def triggers, do: [@camp]

  @impl AreaTriggerScript
  def steps(_trigger_id, _position) do
    [
      %ScriptStep{command: :quest_explored, datalong: @resupplying_the_excavation, condition: unfinished()},
      %ScriptStep{
        command: :start_script,
        datalong: @ambush_script,
        dataint: 100,
        sub_scripts: %{@ambush_script => [saean_turns()]},
        condition:
          all([
            unfinished(),
            nearby(@huldar, @camp_radius),
            nearby(@miran, @camp_radius),
            %{nearby(@ambusher, @ambush_radius) | reverse?: true}
          ])
      }
    ]
  end

  defp saean_turns do
    %ScriptStep{
      command: :start_script,
      datalong: @ambush_script,
      dataint: 100,
      target_type: :nearest_creature_with_entry,
      target_param1: @saean,
      target_param2: @camp_radius,
      swap_final?: true,
      sub_scripts: %{@ambush_script => ambush()}
    }
  end

  defp ambush do
    [%ScriptStep{command: :set_faction, datalong: @dark_iron, datalong2: @restore_on_respawn}] ++
      Enum.map(@ambushers, &ambusher/1) ++
      [
        %ScriptStep{
          command: :attack_start,
          target_type: :nearest_creature_with_entry,
          target_param1: @miran,
          target_param2: @camp_radius
        }
      ]
  end

  defp ambusher(position) do
    %ScriptStep{
      command: :summon_creature,
      datalong: @ambusher,
      datalong2: @ambush_ms,
      dataint3: @nearest_creature,
      dataint4: @timed_or_dead_despawn,
      target_param1: @miran,
      target_param2: @camp_radius,
      position: position
    }
  end

  defp unfinished, do: %Condition{type: :quest_taken, value1: @resupplying_the_excavation, value2: @incomplete}

  defp nearby(entry, radius), do: %Condition{type: :nearby_creature, value1: entry, value2: radius}

  defp all(children), do: %Condition{type: :and, children: children}
end
