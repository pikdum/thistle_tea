defmodule ThistleTea.Game.Entity.Logic.AI.BT.Blackboard do
  @moduledoc """
  Typed per-entity memory shared across behavior-tree ticks.

  Each subsystem owns a dedicated struct so navigation, combat, spell,
  EventAI, and maintenance state cannot accidentally write one another's
  fields.
  """

  alias __MODULE__.Combat
  alias __MODULE__.EventAI
  alias __MODULE__.Maintenance
  alias __MODULE__.Navigation
  alias __MODULE__.Spells

  defstruct navigation: %Navigation{},
            combat: %Combat{},
            spells: %Spells{},
            event_ai: %EventAI{},
            maintenance: %Maintenance{}

  def new, do: %__MODULE__{}

  def ensure(%__MODULE__{} = blackboard), do: blackboard
  def ensure(nil), do: new()

  def ready_for?(%__MODULE__{} = blackboard, key, now) when is_atom(key) and is_integer(now) do
    deadline(blackboard, key) in [nil, 0] or now >= deadline(blackboard, key)
  end

  def delay_until(%__MODULE__{} = blackboard, key, now) when is_atom(key) and is_integer(now) do
    case deadline(blackboard, key) do
      ready_at when is_integer(ready_at) -> max(ready_at - now, 0)
      _ -> 0
    end
  end

  def put_next_at(%__MODULE__{} = blackboard, key, delay_ms, now)
      when is_atom(key) and is_integer(delay_ms) and is_integer(now) do
    put_deadline(blackboard, key, now + delay_ms)
  end

  def put_next_at(%__MODULE__{} = blackboard, _key, _delay_ms, _now), do: blackboard

  def reset_deadline(%__MODULE__{} = blackboard, key) when is_atom(key) do
    put_deadline(blackboard, key, 0)
  end

  def clear_move_target(%__MODULE__{navigation: navigation} = blackboard) do
    %{blackboard | navigation: %{navigation | move_target: nil, target: nil}}
  end

  def clear_waypoint(%__MODULE__{navigation: navigation} = blackboard) do
    %{blackboard | navigation: %{navigation | target: nil, move_target: nil, orientation: nil, wait_time: nil}}
  end

  def clear_chase(%__MODULE__{navigation: navigation} = blackboard) do
    %{blackboard | navigation: %{navigation | chase_started: false, last_target_pos: nil}}
  end

  def spread_attempts(%__MODULE__{combat: %Combat{spread_attempts: attempts}}), do: attempts

  def bump_spread(%__MODULE__{combat: combat} = blackboard) do
    %{blackboard | combat: %{combat | spread_attempts: combat.spread_attempts + 1, spreading: true}}
  end

  def reset_spread(%__MODULE__{combat: combat} = blackboard) do
    %{blackboard | combat: %{combat | spread_attempts: 0, spreading: false}}
  end

  def spreading?(%__MODULE__{combat: %Combat{spreading: spreading}}), do: spreading

  def mark_spreading(%__MODULE__{combat: combat} = blackboard) do
    %{blackboard | combat: %{combat | spreading: true}}
  end

  def clear_spreading(%__MODULE__{combat: combat} = blackboard) do
    %{blackboard | combat: %{combat | spreading: false}}
  end

  def clear_attack(%__MODULE__{combat: combat} = blackboard) do
    combat = %{
      combat
      | next_attack_at: 0,
        attack_started: false,
        auto_attacking: false,
        auto_attack_target: nil
    }

    %{blackboard | combat: combat}
  end

  def reset_spells(%__MODULE__{} = blackboard) do
    %{blackboard | spells: %Spells{}}
  end

  def combat_movement?(%__MODULE__{spells: %Spells{combat_movement: enabled}}), do: enabled

  def run_mode?(%__MODULE__{navigation: %Navigation{run_mode: enabled}}), do: enabled

  def set_run_mode(%__MODULE__{navigation: navigation} = blackboard, enabled) when is_boolean(enabled) do
    %{blackboard | navigation: %{navigation | run_mode: enabled}}
  end

  def set_combat_movement(%__MODULE__{spells: spells} = blackboard, enabled) when is_boolean(enabled) do
    %{blackboard | spells: %{spells | combat_movement: enabled}}
  end

  def spell_timer_ready?(%__MODULE__{spells: %Spells{timers: timers}}, index, now)
      when is_integer(index) and is_integer(now) do
    case timers do
      %{^index => ready_at} when is_integer(ready_at) -> now >= ready_at
      _ -> false
    end
  end

  def put_spell_timer(%__MODULE__{spells: spells} = blackboard, index, delay_ms, now)
      when is_integer(index) and is_integer(delay_ms) and is_integer(now) do
    timers = Map.put(spells.timers || %{}, index, now + delay_ms)
    %{blackboard | spells: %{spells | timers: timers}}
  end

  def fleeing?(%__MODULE__{combat: %Combat{flee_until: flee_until}}), do: is_integer(flee_until)

  def start_flee(%__MODULE__{combat: combat} = blackboard, from_guid, duration_ms, now)
      when is_integer(duration_ms) and is_integer(now) do
    %{blackboard | combat: %{combat | flee_until: now + duration_ms, flee_from: from_guid}}
  end

  def clear_flee(%__MODULE__{combat: combat} = blackboard) do
    %{blackboard | combat: %{combat | flee_until: nil, flee_from: nil}}
  end

  def clear_attack_started(%__MODULE__{combat: combat} = blackboard) do
    %{blackboard | combat: %{combat | attack_started: false}}
  end

  def clear_auto_attack(%__MODULE__{combat: combat} = blackboard) do
    %{blackboard | combat: %{combat | attack_started: false, auto_attacking: false, auto_attack_target: nil}}
  end

  def enable_auto_attack(%__MODULE__{combat: combat} = blackboard, target) do
    %{blackboard | combat: %{combat | auto_attacking: true, auto_attack_target: target}}
  end

  defp deadline(%__MODULE__{navigation: %Navigation{next_chase_at: at}}, :next_chase_at), do: at
  defp deadline(%__MODULE__{navigation: %Navigation{next_wander_at: at}}, :next_wander_at), do: at
  defp deadline(%__MODULE__{navigation: %Navigation{next_waypoint_at: at}}, :next_waypoint_at), do: at
  defp deadline(%__MODULE__{navigation: %Navigation{next_confused_at: at}}, :next_confused_at), do: at
  defp deadline(%__MODULE__{combat: %Combat{next_attack_at: at}}, :next_attack_at), do: at
  defp deadline(%__MODULE__{combat: %Combat{next_offhand_attack_at: at}}, :next_offhand_attack_at), do: at
  defp deadline(%__MODULE__{combat: %Combat{next_aggro_at: at}}, :next_aggro_at), do: at

  defp deadline(%__MODULE__{combat: %Combat{next_call_for_help_at: at}}, :next_call_for_help_at), do: at

  defp deadline(%__MODULE__{combat: %Combat{next_spread_at: at}}, :next_spread_at), do: at
  defp deadline(%__MODULE__{spells: %Spells{next_list_at: at}}, :next_spell_list_at), do: at
  defp deadline(%__MODULE__{event_ai: %EventAI{next_at: at}}, :next_eventai_at), do: at
  defp deadline(%__MODULE__{maintenance: %Maintenance{next_regen_at: at}}, :next_regen_at), do: at

  defp put_deadline(%__MODULE__{navigation: navigation} = blackboard, :next_chase_at, at) do
    %{blackboard | navigation: %{navigation | next_chase_at: at}}
  end

  defp put_deadline(%__MODULE__{navigation: navigation} = blackboard, :next_wander_at, at) do
    %{blackboard | navigation: %{navigation | next_wander_at: at}}
  end

  defp put_deadline(%__MODULE__{navigation: navigation} = blackboard, :next_waypoint_at, at) do
    %{blackboard | navigation: %{navigation | next_waypoint_at: at}}
  end

  defp put_deadline(%__MODULE__{navigation: navigation} = blackboard, :next_confused_at, at) do
    %{blackboard | navigation: %{navigation | next_confused_at: at}}
  end

  defp put_deadline(%__MODULE__{combat: combat} = blackboard, :next_attack_at, at) do
    %{blackboard | combat: %{combat | next_attack_at: at}}
  end

  defp put_deadline(%__MODULE__{combat: combat} = blackboard, :next_offhand_attack_at, at) do
    %{blackboard | combat: %{combat | next_offhand_attack_at: at}}
  end

  defp put_deadline(%__MODULE__{combat: combat} = blackboard, :next_aggro_at, at) do
    %{blackboard | combat: %{combat | next_aggro_at: at}}
  end

  defp put_deadline(%__MODULE__{combat: combat} = blackboard, :next_call_for_help_at, at) do
    %{blackboard | combat: %{combat | next_call_for_help_at: at}}
  end

  defp put_deadline(%__MODULE__{combat: combat} = blackboard, :next_spread_at, at) do
    %{blackboard | combat: %{combat | next_spread_at: at}}
  end

  defp put_deadline(%__MODULE__{spells: spells} = blackboard, :next_spell_list_at, at) do
    %{blackboard | spells: %{spells | next_list_at: at}}
  end

  defp put_deadline(%__MODULE__{event_ai: event_ai} = blackboard, :next_eventai_at, at) do
    %{blackboard | event_ai: %{event_ai | next_at: at}}
  end

  defp put_deadline(%__MODULE__{maintenance: maintenance} = blackboard, :next_regen_at, at) do
    %{blackboard | maintenance: %{maintenance | next_regen_at: at}}
  end
end
