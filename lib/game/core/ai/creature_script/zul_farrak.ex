defmodule ThistleTea.Game.Core.AI.CreatureScript.ZulFarrak do
  @moduledoc """
  vmangos `npc_sergeant_bly` and `npc_weegli_blastfuse`, Sergeant Bly's crew
  in Zul'Farrak.

  Once the trolls' cages open, the crew climbs to the top of the pyramid
  stairs. Weegli reaches the top first, cries out, and starts the trolls'
  waves through the instance's pyramid phase (`InstanceScript.ZulFarrak`). If
  a fight keeps Weegli off the stairs, Weegli starts them on getting home.

  Bly and Weegli greet a player by how far the pyramid has gone. With every
  troll dead, Weegli offers to blow the end door, and Bly offers a fight.
  Picking Weegli's offer sends Weegli running to the door. There Weegli plants
  a charge, runs clear, sets it off, and opens the door to Chief Ukorz
  Sandscalp. Then Weegli runs off and is gone. Each leg of the run makes its
  end Weegli's home, as vmangos sets the combat start position. Unlike
  vmangos, a Weegli whom a fight pulls off a leg carries on from there after
  walking home. Picking Bly's fight makes him talk for ten seconds. Then
  Weegli runs off to blow the door anyway, and Raven, Oro, Murta, and Bly turn
  on the player. vmangos swaps the crew's factions within one update, but here
  each swap lands on its own, so every member passes through a faction that
  is friendly to all on the way. That way no swap pits the crew against each
  other.

  In a fight, Bly bashes and takes revenge and Weegli throws bombs.

  vmangos `ward_zumrah`: a Ward of Zum'rah raises a Skeleton of Zum'rah every
  five seconds for as long as it stands, in a fight or out.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @bly 7_604
  @raven 7_605
  @oro 7_606
  @weegli 7_607
  @murta 7_608
  @ward_of_zumrah 7_785
  @summon_skeleton 11_088
  @triggered 0x02
  @skeleton_ms 5_000

  @pyramid 1
  @end_door 3
  @not_started 0
  @cages_open 1
  @arrived_at_stair 2
  @killed_all_trolls 8
  @done 3

  @hostile 14
  @friendly 35
  @explosive_charge 144_065
  @charge_seconds 300
  @active 0

  @shield_bash 11_972
  @revenge 12_170
  @bomb 8_858

  @say_betrayed 3_882
  @say_never_liked_you 3_884
  @say_out_of_here 3_811
  @say_here_they_come 3_744
  @say_here_i_go 3_785

  @point_motion 9
  @at_stair 1
  @stair_watch 2
  @at_door 10
  @clear_of_blast 11
  @gone 12

  @pathfind 0x1
  @walk 0x2
  @run 0x4
  @inform 0x2
  @crew_radius 100
  @charge_radius 40
  @arrival_radius 3

  @door {1_858.57, 1_146.35, 14.745, 0.0}
  @clear {1_863.77, 1_176.99, 9.993, 0.0}
  @away {1_827.1, 1_184.0, 8.993, 0.0}

  @bly_fight "That's it! I'm tired of helping you out.  It's time we settled things on the battlefield!"
  @weegli_door "Will you blow up that door now?"

  @impl CreatureScript
  def entries, do: [@bly, @weegli, @ward_of_zumrah]

  @impl CreatureScript
  def events(@bly = entry) do
    [
      CreatureScript.event(entry, 1, :timer_in_combat, [cast(@shield_bash)],
        param1: 5_000,
        param2: 5_000,
        param3: 15_000,
        param4: 15_000
      ),
      CreatureScript.event(entry, 2, :timer_in_combat, [cast(@revenge)],
        param1: 8_000,
        param2: 8_000,
        param3: 10_000,
        param4: 10_000
      )
    ]
  end

  def events(@ward_of_zumrah = entry) do
    raise_skeleton = [
      %ScriptStep{command: :cast_spell, datalong: @summon_skeleton, datalong2: @triggered, target_self?: true}
    ]

    timer = [param1: @skeleton_ms, param2: @skeleton_ms, param3: @skeleton_ms, param4: @skeleton_ms]

    [
      CreatureScript.event(entry, 1, :timer_ooc, raise_skeleton, timer),
      CreatureScript.event(entry, 2, :timer_in_combat, raise_skeleton, timer)
    ]
  end

  def events(@weegli = entry) do
    [
      CreatureScript.event(entry, 1, :movement_inform, arrive_at_stair(), param1: @point_motion, param2: @at_stair),
      CreatureScript.event(entry, 2, :reached_home, arrive_at_stair(), condition: pyramid(@cages_open)),
      CreatureScript.event(entry, 3, :movement_inform, watch_stairs(), param1: @point_motion, param2: @stair_watch),
      CreatureScript.event(entry, 4, :movement_inform, plant_charge(), param1: @point_motion, param2: @at_door),
      CreatureScript.event(entry, 5, :movement_inform, blow_door(), param1: @point_motion, param2: @clear_of_blast),
      CreatureScript.event(entry, 6, :movement_inform, [%ScriptStep{command: :despawn}],
        param1: @point_motion,
        param2: @gone
      ),
      CreatureScript.event(entry, 7, :timer_in_combat, [cast(@bomb)],
        param1: 10_000,
        param2: 10_000,
        param3: 10_000,
        param4: 10_000
      ),
      CreatureScript.event(entry, 8, :reached_home, plant_charge(), condition: at(@door)),
      CreatureScript.event(entry, 9, :reached_home, blow_door(), condition: at(@clear)),
      CreatureScript.event(entry, 10, :reached_home, [%ScriptStep{command: :despawn}], condition: at(@away))
    ]
  end

  @impl CreatureScript
  def gossip do
    %{
      @bly => %Gossip{
        texts: [
          %Gossip.Text{text_id: 1_516},
          %Gossip.Text{text_id: 1_515, condition: pyramid(@not_started)},
          %Gossip.Text{text_id: 1_517, condition: pyramid(@killed_all_trolls)}
        ],
        options: [%Gossip.Option{text: @bly_fight, condition: pyramid(@killed_all_trolls), steps: betrayal()}]
      },
      @weegli => %Gossip{
        texts: [
          %Gossip.Text{text_id: 1_513},
          %Gossip.Text{text_id: 1_511, condition: pyramid(@not_started)},
          %Gossip.Text{text_id: 1_514, condition: pyramid(@killed_all_trolls)}
        ],
        options: [%Gossip.Option{text: @weegli_door, condition: pyramid(@killed_all_trolls), steps: run_to_door()}]
      }
    }
  end

  defp arrive_at_stair do
    [
      talk(@say_here_they_come),
      %ScriptStep{command: :set_instance_data, datalong: @pyramid, datalong2: @arrived_at_stair},
      home({1_882.69, 1_272.28, 41.87, 4.7}),
      move({1_883.27, 1_268.72, 41.73, 0.0}, @run, @stair_watch)
    ]
  end

  defp watch_stairs do
    stair_watch = {1_888.55, 1_272.19, 41.67, 4.7}
    [home(stair_watch), move(stair_watch, @walk, 0)]
  end

  defp run_to_door,
    do: [CreatureScript.faction(@friendly), talk(@say_here_i_go), home(@door), move(@door, @run, @at_door)]

  defp plant_charge do
    [
      %ScriptStep{
        command: :summon_object,
        datalong: @explosive_charge,
        datalong2: @charge_seconds,
        position: {1_856.314209, 1_144.990479, 15.486275, 5.6635}
      },
      home(@clear),
      move(@clear, @run, @clear_of_blast)
    ]
  end

  defp blow_door do
    [
      %ScriptStep{
        command: :set_game_object_state,
        datalong: @active,
        target_type: :nearest_game_object_with_entry,
        target_param1: @explosive_charge,
        target_param2: @charge_radius
      },
      %ScriptStep{command: :set_instance_data, datalong: @end_door, datalong2: @done},
      home(@away),
      move(@away, @run, @gone)
    ]
  end

  defp betrayal do
    [
      talk(@say_betrayed),
      %{talk(@say_never_liked_you) | delay_ms: 5_000},
      on_crew(@weegli, talk(@say_out_of_here)),
      on_crew(@weegli, CreatureScript.timed(run_to_door()))
    ] ++ turn_crew(@friendly) ++ turn_crew(@hostile) ++ [%ScriptStep{command: :attack_start, delay_ms: 10_000}]
  end

  defp turn_crew(faction) do
    Enum.map([@raven, @oro, @murta], &on_crew(&1, CreatureScript.faction(faction))) ++
      [%{CreatureScript.faction(faction) | delay_ms: 10_000}]
  end

  defp on_crew(entry, %ScriptStep{} = step) do
    %{
      step
      | delay_ms: 10_000,
        target_type: :nearest_creature_with_entry,
        target_param1: entry,
        target_param2: @crew_radius,
        swap_final?: true
    }
  end

  defp at({x, y, z, _o}),
    do: %Condition{
      type: :distance_to_position,
      value1: x,
      value2: y,
      value3: z,
      value4: @arrival_radius,
      swap_targets?: true
    }

  defp pyramid(phase), do: %Condition{type: :instance_data, value1: @pyramid, value2: phase, value3: 0}

  defp cast(spell_id), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: :victim}

  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}

  defp home(position), do: %ScriptStep{command: :set_home_position, position: position}

  defp move(position, pace, 0),
    do: %ScriptStep{command: :move_to, datalong3: Bitwise.bor(@pathfind, pace), position: position}

  defp move(position, pace, point),
    do: %ScriptStep{
      command: :move_to,
      datalong3: Bitwise.bor(@pathfind, pace),
      datalong4: @inform,
      dataint: point,
      position: position
    }
end
