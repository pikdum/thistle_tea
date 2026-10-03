defmodule ThistleTea.Game.Core.AI.CreatureScript.Piznik do
  @moduledoc """
  vmangos `npc_piznik`, the Windshear Mine goblin behind Gerenzo's Orders
  (1090) in the Stonetalon Mountains.

  Accepting the quest opens Piznik to attack and sets the Windshear goblins on
  him in three waves a minute apart: two at once, then three, then three led
  by a geomancer. If he is still standing three minutes in, the quest
  completes for the player who accepted it and their group, and Piznik goes
  back to his work. His death fails the quest.

  The accepting player is kept as the target of a scripted map event named
  after the quest, which also keeps a second player from starting the defense
  while one is under way. The goblins charge Piznik directly instead of
  walking to his side first.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @piznik 4_276
  @vermin 3_998
  @tunnel_rat 4_001
  @geomancer 4_003
  @gerenzos_orders 1_090

  @escort_faction 495
  @template_faction 0
  @unit_flags_field 46
  @immune_to_npc 0x200
  @pvp 0x1000
  @add_flags 1
  @remove_flags 2

  @idle 0
  @defending 1

  @event_limit_s 300
  @first_wave_ms 1_000
  @wave_interval_ms 60_000
  @defense_ms 180_000
  @summon_ms 120_000
  @timed_or_corpse_despawn 2
  @attack_self 8

  @left_flank {935.693, -262.079, -2.155, 0.5}
  @right_flank {931.674, -261.397, -2.020, 0.217}
  @rear {930.422, -266.460, -1.669, 0.5}

  @waves [
    [{@vermin, @left_flank}, {@tunnel_rat, @right_flank}],
    [{@vermin, @left_flank}, {@tunnel_rat, @right_flank}, {@vermin, @rear}],
    [{@vermin, @left_flank}, {@tunnel_rat, @right_flank}, {@geomancer, @rear}]
  ]

  @impl CreatureScript
  def entries, do: [@piznik]

  @impl CreatureScript
  def events(@piznik) do
    [
      CreatureScript.event(@piznik, 1, :death, [fail_quest(), end_event()],
        inverse_phase_mask: CreatureScript.only_in_phases([@defending])
      )
    ]
  end

  @impl CreatureScript
  def quest_start_steps do
    %{
      @gerenzos_orders => [
        %ScriptStep{
          command: :start_map_event,
          datalong: @gerenzos_orders,
          datalong2: @event_limit_s,
          abort_on_failure?: true
        },
        %ScriptStep{command: :set_phase, datalong: @defending},
        unit_flags(@pvp, @add_flags),
        unit_flags(@immune_to_npc, @remove_flags),
        CreatureScript.faction(@escort_faction),
        CreatureScript.timed(waves() ++ hold())
      ]
    }
  end

  defp waves do
    @waves
    |> Enum.with_index()
    |> Enum.flat_map(fn {wave, index} ->
      delay_ms = max(index * @wave_interval_ms, @first_wave_ms)
      Enum.map(wave, &%{summon(&1) | delay_ms: delay_ms, condition: defending()})
    end)
  end

  defp hold do
    Enum.map(
      [
        credit(),
        unit_flags(@pvp, @remove_flags),
        unit_flags(@immune_to_npc, @add_flags),
        CreatureScript.faction(@template_faction),
        %ScriptStep{command: :set_phase, datalong: @idle},
        end_event()
      ],
      &%{&1 | delay_ms: @defense_ms, condition: defending()}
    )
  end

  defp summon({entry, position}) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: @summon_ms,
      dataint3: @attack_self,
      dataint4: @timed_or_corpse_despawn,
      position: position
    }
  end

  defp defending, do: %Condition{type: :map_event_active, value1: @gerenzos_orders}

  defp credit do
    %ScriptStep{
      command: :quest_explored,
      datalong: @gerenzos_orders,
      datalong3: 1,
      target_type: :map_event_target,
      target_param1: @gerenzos_orders
    }
  end

  defp fail_quest do
    %ScriptStep{
      command: :fail_quest,
      datalong: @gerenzos_orders,
      target_type: :map_event_target,
      target_param1: @gerenzos_orders
    }
  end

  defp end_event, do: %ScriptStep{command: :end_map_event, datalong: @gerenzos_orders}

  defp unit_flags(flags, mode),
    do: %ScriptStep{command: :modify_flags, datalong: @unit_flags_field, datalong2: flags, datalong3: mode}
end
