defmodule ThistleTea.Game.Core.AI.AreaTriggerScript.ZulFarrak do
  @moduledoc """
  vmangos `at_zumrah` and `at_antusul`, the two Zul'Farrak triggers that wake a
  boss.

  Stepping near Witch Doctor Zum'rah's sanctum turns him hostile and open to
  attack, and he demands to know how the intruder dares. Coming within sight
  of Antu'sul's basin makes him call his children to lunch. Four Sul'lithuz
  Broodlings hatch around the basin and go for everyone in the dungeon, and
  Antu'sul comes down to the basin floor. vmangos hatches four broodlings from
  patch 1.12 on, as here.

  Each trigger fires once per copy, through the Zum'rah and Antu'sul fields
  of the instance data, and only while its boss is near.
  """

  @behaviour ThistleTea.Game.Core.AI.AreaTriggerScript

  alias ThistleTea.Game.Core.AI.AreaTriggerScript
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @near_zumrah 962
  @near_antusul 1_447

  @zumrah_field 4
  @antusul_field 5
  @in_progress 1

  @zumrah 7_271
  @zumrah_reach 30
  @zumrah_hostile 37
  @say_how_dare_you 3_622
  @unit_flags_field 46
  @immune_to_player 0x100
  @remove_flags 2

  @antusul 8_127
  @antusul_reach 100
  @broodling 8_138
  @say_lunch 4_166
  @broodling_ms 25_000
  @attack_provided 0
  @timed_or_dead_despawn 1
  @hatch_script 1
  @basin_floor {1_805.133667, 740.349304, 14.763382, 0.0}
  @pathfind_run 0x5

  @nests [
    {1_823.415161, 748.297485, 20.794931, 3.944444},
    {1_786.019165, 743.399048, 15.481779, 6.108652},
    {1_827.460571, 738.032410, 19.131363, 3.385939},
    {1_810.196533, 749.873230, 17.597878, 4.555309}
  ]

  @impl AreaTriggerScript
  def triggers, do: [@near_zumrah, @near_antusul]

  @impl AreaTriggerScript
  def steps(@near_zumrah, _position) do
    once(@zumrah_field, @zumrah, @zumrah_reach, [
      %ScriptStep{
        command: :modify_flags,
        datalong: @unit_flags_field,
        datalong2: @immune_to_player,
        datalong3: @remove_flags
      },
      CreatureScript.faction(@zumrah_hostile),
      %ScriptStep{command: :talk, dataint: @say_how_dare_you}
    ])
  end

  def steps(@near_antusul, _position) do
    once(@antusul_field, @antusul, @antusul_reach, [
      %ScriptStep{command: :talk, dataint: @say_lunch}
      | Enum.map(@nests, &hatch/1) ++
          [%ScriptStep{command: :move_to, datalong3: @pathfind_run, position: @basin_floor}]
    ])
  end

  defp once(field, boss, reach, boss_steps) do
    [
      %ScriptStep{
        command: :start_script,
        datalong: 1,
        dataint: 100,
        condition: %Condition{
          type: :and,
          children: [
            %Condition{type: :instance_data, value1: field, value2: 0, value3: 0},
            %Condition{type: :nearby_creature, value1: boss, value2: reach}
          ]
        },
        sub_scripts: %{
          1 => [
            %ScriptStep{command: :set_instance_data, datalong: field, datalong2: @in_progress},
            %{
              CreatureScript.timed(boss_steps)
              | target_type: :nearest_creature_with_entry,
                target_param1: boss,
                target_param2: reach,
                swap_final?: true
            }
          ]
        }
      }
    ]
  end

  defp hatch(position) do
    %ScriptStep{
      command: :summon_creature,
      datalong: @broodling,
      datalong2: @broodling_ms,
      dataint2: @hatch_script,
      dataint3: @attack_provided,
      dataint4: @timed_or_dead_despawn,
      position: position,
      sub_scripts: %{@hatch_script => [%ScriptStep{command: :zone_combat_pulse, datalong: 1}]}
    }
  end
end
