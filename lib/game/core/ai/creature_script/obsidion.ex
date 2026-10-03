defmodule ThistleTea.Game.Core.AI.CreatureScript.Obsidion do
  @moduledoc """
  vmangos `npc_obsidion` and `npc_dying_archaeologist`, Rise, Obsidion!
  (3566) in the Searing Gorge.

  Obsidion lies in pieces, out of the players' reach, until someone takes
  the quest from the Dying Archaeologist. Then Dorius walks up and speaks
  his piece, reveals himself as Lathoric the Black, and calls the golem to
  its feet: both turn on the nearest enemy player, Obsidion smashing the
  ground and knocking foes away. Lathoric carries the head the quest wants
  and only exists for these three minutes. Obsidion falls back to its
  pieces when the fight ends, and stays put for a second taker while the
  first scene is still running.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @obsidion 8_400
  @dorius 8_421
  @lathoric 8_391
  @quest 3_566

  @dorius_spawn {-6_460.25, -1_244.86, 180.36, 3.04}
  @dorius_lines [4_393, 4_394, 4_395, 4_396, 4_397, 4_398]
  @lathoric_line 4_391
  @ground_smash 12_734
  @knock_away 10_101

  @scene 1
  @dorius_scene 840_001
  @rally 2
  @first_line_ms 5_000
  @line_gap_ms 6_000
  @unmask_after_ms 1_000
  @scene_lifetime_ms 180_000
  @timed_or_dead_despawn 1
  @scene_yards 30
  @unit_flags 46
  @immune_to_player 0x100
  @add_flags 1
  @remove_flags 2
  @standing 0
  @lying_dead 7

  @impl CreatureScript
  def entries, do: [@obsidion]

  @impl CreatureScript
  def events(@obsidion = entry) do
    [
      CreatureScript.event(entry, 1, :spawned, [lie_dead(), immune(@add_flags)]),
      CreatureScript.event(entry, 2, :evade, [immune(@add_flags)]),
      CreatureScript.event(entry, 3, :reached_home, [lie_dead()]),
      CreatureScript.event(entry, 4, :aggro, [immune(@remove_flags)]),
      timer(entry, 5, @ground_smash, 8_000),
      timer(entry, 6, @knock_away, 12_000)
    ]
  end

  @impl CreatureScript
  def quest_start_steps do
    %{
      @quest => [
        %ScriptStep{
          command: :start_script,
          datalong: @scene,
          dataint: 100,
          target_type: :nearest_creature_with_entry,
          target_param1: @obsidion,
          target_param2: @scene_yards,
          swap_final?: true,
          condition: %Condition{type: :and, children: [obsidion_alive(), scene_idle()]},
          sub_scripts: %{@scene => [summon_dorius()]}
        }
      ]
    }
  end

  defp summon_dorius do
    %ScriptStep{
      command: :summon_creature,
      datalong: @dorius,
      datalong2: @scene_lifetime_ms,
      dataint2: @dorius_scene,
      dataint4: @timed_or_dead_despawn,
      position: @dorius_spawn,
      sub_scripts: %{@dorius_scene => [CreatureScript.timed(dorius_scene())]}
    }
  end

  defp dorius_scene do
    lines =
      @dorius_lines
      |> Enum.with_index()
      |> Enum.map(fn {text, index} -> %{talk(text) | delay_ms: @first_line_ms + index * @line_gap_ms} end)

    last_line_ms = @first_line_ms + (length(@dorius_lines) - 1) * @line_gap_ms
    unmasked_ms = last_line_ms + @unmask_after_ms
    attack_ms = last_line_ms + @line_gap_ms

    attack =
      Enum.map(
        [
          talk(@lathoric_line),
          obsidion(%ScriptStep{command: :stand_state, datalong: @standing}),
          obsidion(immune(@remove_flags)),
          obsidion(%ScriptStep{
            command: :start_script,
            datalong: @rally,
            dataint: 100,
            sub_scripts: %{@rally => [attack_nearest_player()]}
          }),
          immune(@remove_flags),
          attack_nearest_player()
        ],
        &%{&1 | delay_ms: attack_ms}
      )

    lines ++ [%ScriptStep{command: :update_entry, datalong: @lathoric, delay_ms: unmasked_ms} | attack]
  end

  defp obsidion(%ScriptStep{} = step) do
    %{
      step
      | target_type: :nearest_creature_with_entry,
        target_param1: @obsidion,
        target_param2: @scene_yards,
        swap_final?: true
    }
  end

  defp obsidion_alive, do: %Condition{type: :alive, swap_targets?: true}

  defp scene_idle do
    %Condition{
      type: :or,
      reverse?: true,
      children: [
        %Condition{type: :nearby_creature, value1: @dorius, value2: @scene_yards},
        %Condition{type: :nearby_creature, value1: @lathoric, value2: @scene_yards}
      ]
    }
  end

  defp attack_nearest_player, do: %ScriptStep{command: :attack_start, target_type: :nearest_hostile_player}

  defp lie_dead, do: %ScriptStep{command: :stand_state, datalong: @lying_dead}

  defp immune(mode),
    do: %ScriptStep{command: :modify_flags, datalong: @unit_flags, datalong2: @immune_to_player, datalong3: mode}

  defp timer(entry, index, spell_id, every_ms) do
    CreatureScript.event(entry, index, :timer_in_combat, [cast(spell_id)],
      param1: every_ms,
      param2: every_ms,
      param3: every_ms,
      param4: every_ms
    )
  end

  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}
  defp cast(spell_id), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: :victim}
end
