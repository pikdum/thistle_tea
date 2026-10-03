defmodule ThistleTea.Game.Core.AI.CreatureScript.KindalMoonweaver do
  @moduledoc """
  vmangos `npc_kindal_moonweaver` and `npc_captured_sprite_darter`, Freedom
  for All Creatures (2969) in Feralas.

  Accepting the quest gets Kindal Moonweaver to her feet and, three seconds
  later, following the player into the Grimtotem camp. The player opens the
  sprite darters' cage with the Bamboo Cage Key, and every captured sprite
  darter near it takes off, a moment apart, along one of eleven escape
  routes out of the camp, fighting whatever catches it and carrying on once
  the fight is over. Six sprites getting away completes the quest; a sixth
  sprite dying fails it, and so do Kindal dying, the player leaving her more
  than 100 yards behind, and the quest's six minutes running out. Either way
  Kindal goes home.

  The quest's map event follows Kindal; a second map event, keyed by the
  sprite darter entry, counts the sprites saved and lost and ends the first
  with its outcome. Every step of the second checks that the quest's event
  is still running, so it falls silent once Kindal has gone home.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Route
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @kindal 7_956
  @sprite 7_997
  @quest 2_969
  @sprite_event @sprite

  @begin 4_079
  @success 4_080
  @sprites_lost 4_081
  @out_of_time 5_285
  @aggro [4_122, 4_123, 4_124, 4_125]

  @kindal_faction 231
  @sprite_faction 10
  @saved 0
  @died 1
  @sprites_needed 6
  @time_limit_s 360
  @sprite_event_limit_s 3_600
  @sight_distance 100
  @follow_delay_ms 3_000
  @corpse_despawn_ms 10_000
  @linger_ms 30_000
  @max_start_delay_ms 3_000

  @success_script 1
  @failure_script 2
  @quiet_failure_script 3
  @source_dead 1
  @group_credit 1
  @event_success 1
  @event_failure 0
  @keep -1
  @unit_flags 46
  @npc_flags 147
  @immune_to_npc 0x200
  @all_flags 0xFFFF_FFFF
  @remove_flags 2
  @stand 0
  @idle_motion 0
  @follow_motion 15
  @script_route 5

  @move_points {
    {-4531.78, 807.50, 59.92},
    {-4513.14, 765.45, 60.72},
    {-4529.44, 825.49, 60.51},
    {-4563.52, 877.13, 61.07},
    {-4578.42, 891.02, 65.79},
    {-4592.71, 890.61, 69.11},
    {-4582.46, 751.20, 49.65},
    {-4572.83, 741.11, 45.69},
    {-4557.85, 730.01, 45.57},
    {-4529.02, 706.96, 60.70},
    {-4515.88, 696.60, 64.38}
  }

  @escape_routes [{2, 3}, {2, 4}, {2, 5}, {0, 6}, {0, 7}, {0, 8}, {1, 6}, {1, 7}, {1, 8}, {1, 9}, {1, 10}]

  @impl CreatureScript
  def entries, do: [@kindal, @sprite]

  @impl CreatureScript
  def events(@kindal) do
    [
      CreatureScript.event(@kindal, 1, :aggro, [aggro_talk(@aggro)])
    ]
  end

  def events(@sprite) do
    [
      CreatureScript.event(@sprite, 1, :death, [
        count(@died),
        CreatureScript.timed([%ScriptStep{command: :despawn, delay_ms: @corpse_despawn_ms}])
      ])
    ]
  end

  @impl CreatureScript
  def quest_start_steps do
    %{
      @quest => [
        quest_event(),
        sprite_event(),
        %ScriptStep{command: :stand_state, datalong: @stand},
        %ScriptStep{command: :turn_to},
        flags(@unit_flags, @immune_to_npc),
        %ScriptStep{command: :talk, dataint: @begin},
        CreatureScript.faction(@kindal_faction),
        flags(@npc_flags, @all_flags),
        %ScriptStep{
          command: :movement,
          datalong: @follow_motion,
          position: {2.0, 0.0, 0.0, :math.pi() / 2},
          delay_ms: @follow_delay_ms
        }
      ]
    }
  end

  @impl CreatureScript
  def routes do
    @escape_routes
    |> Enum.with_index(1)
    |> Enum.map(fn {{from, to}, variant} ->
      %Route{
        entry: @sprite,
        variant: variant,
        path: [move_point(from), move_point(to)],
        points: %{1 => [count(@saved), %ScriptStep{command: :despawn}]}
      }
    end)
  end

  def escape_steps do
    starts =
      @escape_routes
      |> Enum.with_index(1)
      |> Enum.map(fn {_route, variant} ->
        [
          %ScriptStep{
            command: :start_waypoints,
            datalong: @script_route,
            dataint3: variant,
            delay_ms: div((variant - 1) * @max_start_delay_ms, length(@escape_routes))
          }
        ]
      end)

    [CreatureScript.faction(@sprite_faction), %ScriptStep{command: :set_run, datalong: 1}] ++
      CreatureScript.pick(starts)
  end

  defp quest_event do
    %ScriptStep{
      command: :start_map_event,
      datalong: @quest,
      datalong2: @time_limit_s,
      dataint2: @success_script,
      dataint4: @failure_script,
      abort_on_failure?: true,
      failure_condition: %Condition{type: :escort, value1: @source_dead, value2: @sight_distance},
      sub_scripts: %{
        @success_script => [
          %ScriptStep{command: :movement, datalong: @idle_motion},
          %ScriptStep{command: :quest_explored, datalong: @quest, datalong2: @sight_distance, datalong3: @group_credit},
          %ScriptStep{command: :talk, dataint: @success},
          %ScriptStep{command: :despawn, delay_ms: @linger_ms}
        ],
        @failure_script => [
          %ScriptStep{command: :fail_quest, datalong: @quest},
          %ScriptStep{
            command: :talk,
            dataint: @out_of_time,
            condition: %Condition{type: :alive, swap_targets?: true}
          },
          %ScriptStep{command: :end_map_event, datalong: @sprite_event, datalong2: @event_failure},
          %ScriptStep{command: :respawn_creature, datalong: 1}
        ]
      }
    }
  end

  defp sprite_event do
    %ScriptStep{
      command: :start_map_event,
      datalong: @sprite_event,
      datalong2: @sprite_event_limit_s,
      dataint2: @success_script,
      dataint4: @failure_script,
      success_condition: event_data(@saved),
      failure_condition: event_data(@died),
      sub_scripts: %{
        @success_script => while_escorting([end_quest_event(@event_success)]),
        @failure_script =>
          while_escorting([
            %ScriptStep{command: :talk, dataint: @sprites_lost},
            %ScriptStep{command: :fail_quest, datalong: @quest},
            %ScriptStep{
              command: :edit_map_event,
              datalong: @quest,
              dataint: @keep,
              dataint2: @keep,
              dataint3: @keep,
              dataint4: @quiet_failure_script,
              sub_scripts: %{
                @quiet_failure_script => [
                  %ScriptStep{command: :movement, datalong: @idle_motion},
                  %ScriptStep{command: :despawn, delay_ms: @linger_ms}
                ]
              }
            },
            end_quest_event(@event_failure)
          ])
      }
    }
  end

  defp aggro_talk([first, second, third, fourth]),
    do: %ScriptStep{command: :talk, dataint: first, dataint2: second, dataint3: third, dataint4: fourth}

  defp end_quest_event(outcome), do: %ScriptStep{command: :end_map_event, datalong: @quest, datalong2: outcome}

  defp while_escorting(steps) do
    Enum.map(steps, &%{&1 | condition: %Condition{type: :map_event_active, value1: @quest}})
  end

  defp count(index) do
    %ScriptStep{command: :set_map_event_data, datalong: @sprite_event, datalong2: index, datalong3: 1, datalong4: 1}
  end

  defp event_data(index) do
    %Condition{type: :map_event_data, value1: @sprite_event, value2: index, value3: @sprites_needed, value4: 1}
  end

  defp flags(field, mask),
    do: %ScriptStep{command: :modify_flags, datalong: field, datalong2: mask, datalong3: @remove_flags}

  defp move_point(index) do
    {x, y, z} = elem(@move_points, index)
    {x, y, z, 0}
  end
end
