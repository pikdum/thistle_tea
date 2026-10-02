defmodule ThistleTea.Game.Core.AI.CreatureScript.LazyPeon do
  @moduledoc """
  vmangos `LazyPeons` (Durotar), the target of quest 5441 "Lazy Peons".

  A peon sleeps under 17743 until Foreman's Blackjack (19938) wakes it. The
  sleep aura only lasts two minutes, so a sleeping peon recasts it whenever it
  lapses, as the C++ `STATE_SLEEPING` update does. The caster gets kill credit
  for the peon. Three seconds later the peon gets up, and two seconds after
  that it grumbles at the player and walks to the nearest lumber pile. It
  chops wood for two minutes, walks home, and falls asleep again.

  Phases stand in for the C++ state machine, so a peon that is already awake
  can't be credited again:

  | phase | state |
  |---|---|
  | 0 | asleep |
  | 1 | walking to the pile |
  | 2 | working, or walking home |
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @peon 10_556
  @sleep 17_743
  @awaken 19_938
  @lumber_pile 175_784
  @pile_search_radius 20
  @pile_contact_distance 0.7
  @say_woken 5_774
  @work_emote 234
  @wake_ms 3_000
  @walk_ms 5_000
  @work_ms 120_000
  @resleep_ms 1_000
  @aura_not_present 0x20
  @point_motion 9
  @pile_point 1
  @distance_from_target 2
  @pathfind_walk 3
  @inform_on_arrival 2
  @home_motion 7

  @impl CreatureScript
  def entries, do: [@peon]

  @impl CreatureScript
  def events(entry) do
    [
      CreatureScript.event(entry, 1, :timer_ooc, [sleep()],
        param1: 0,
        param2: 0,
        param3: @resleep_ms,
        param4: @resleep_ms,
        inverse_phase_mask: CreatureScript.only_in_phases([0])
      ),
      CreatureScript.event(entry, 2, :hit_by_spell, wake_up(),
        param1: @awaken,
        inverse_phase_mask: CreatureScript.only_in_phases([0])
      ),
      CreatureScript.event(entry, 3, :movement_inform, work(),
        param1: @point_motion,
        param2: @pile_point,
        inverse_phase_mask: CreatureScript.only_in_phases([1])
      ),
      CreatureScript.event(entry, 4, :reached_home, [sleep(), phase(0)])
    ]
  end

  defp wake_up do
    [
      %ScriptStep{command: :kill_credit, datalong: @peon},
      phase(1),
      CreatureScript.timed([
        %ScriptStep{command: :remove_aura, datalong: @sleep, delay_ms: @wake_ms},
        %ScriptStep{command: :talk, dataint: @say_woken, delay_ms: @walk_ms},
        %ScriptStep{
          command: :move_to,
          delay_ms: @walk_ms,
          datalong: @distance_from_target,
          datalong3: @pathfind_walk,
          datalong4: @inform_on_arrival,
          dataint: @pile_point,
          position: {@pile_contact_distance, 0.0, 0.0, -1.0}
        }
        |> at_lumber_pile()
      ])
    ]
  end

  defp work do
    [
      at_lumber_pile(%ScriptStep{command: :turn_to}),
      %ScriptStep{command: :emote, datalong: @work_emote},
      phase(2),
      CreatureScript.timed([
        %ScriptStep{command: :emote, datalong: 0, delay_ms: @work_ms},
        %ScriptStep{command: :movement, datalong: @home_motion, delay_ms: @work_ms}
      ])
    ]
  end

  defp sleep, do: %ScriptStep{command: :cast_spell, datalong: @sleep, datalong2: @aura_not_present, target_self?: true}

  defp phase(phase), do: %ScriptStep{command: :set_phase, datalong: phase}

  defp at_lumber_pile(%ScriptStep{} = step) do
    %{
      step
      | target_type: :nearest_game_object_with_entry,
        target_param1: @lumber_pile,
        target_param2: @pile_search_radius
    }
  end
end
