defmodule ThistleTea.Game.Entity.Logic.AI.BT.Blackboard do
  @moduledoc """
  Per-entity scratch state shared across behavior-tree ticks: current targets
  and per-key next-run timestamps used to pace actions between ticks.
  """
  defstruct target: nil,
            move_target: nil,
            orientation: nil,
            wait_time: nil,
            last_target_pos: nil,
            chase_started: false,
            next_chase_at: 0,
            next_attack_at: 0,
            next_offhand_attack_at: 0,
            attack_started: false,
            auto_attacking: false,
            next_wander_at: 0,
            next_waypoint_at: 0,
            next_aggro_at: 0,
            next_confused_at: 0,
            next_regen_at: 0,
            next_spread_at: 0,
            spread_attempts: 0,
            spreading: false,
            confused_anchor: nil,
            spell_timers: nil,
            next_spell_list_at: 0,
            combat_movement: true,
            eventai_phase: 0,
            run_mode: false,
            eventai_timers: nil,
            eventai_disabled: nil,
            next_eventai_at: 0,
            flee_until: nil,
            flee_from: nil

  def new do
    %__MODULE__{}
  end

  def from_any(%__MODULE__{} = blackboard), do: blackboard
  def from_any(nil), do: new()

  def from_any(%{} = data) do
    struct(__MODULE__, data)
  end

  def ready_for?(%__MODULE__{} = blackboard, key, now) when is_atom(key) and is_integer(now) do
    case Map.get(blackboard, key) do
      nil -> true
      0 -> true
      ready_at -> now >= ready_at
    end
  end

  def delay_until(%__MODULE__{} = blackboard, key, now) when is_atom(key) and is_integer(now) do
    case Map.get(blackboard, key) do
      nil -> 0
      0 -> 0
      ready_at when is_integer(ready_at) -> max(ready_at - now, 0)
      _ -> 0
    end
  end

  def put_next_at(%__MODULE__{} = blackboard, key, delay_ms, now)
      when is_atom(key) and is_integer(delay_ms) and is_integer(now) do
    Map.put(blackboard, key, now + delay_ms)
  end

  def put_next_at(%__MODULE__{} = blackboard, _key, _delay_ms, _now) do
    blackboard
  end

  def clear_move_target(%__MODULE__{} = blackboard) do
    %{blackboard | move_target: nil, target: nil}
  end

  def clear_waypoint(%__MODULE__{} = blackboard) do
    %{blackboard | target: nil, move_target: nil, orientation: nil, wait_time: nil}
  end

  def clear_chase(%__MODULE__{} = blackboard) do
    %{blackboard | chase_started: false, last_target_pos: nil}
  end

  def spread_attempts(%__MODULE__{} = blackboard) do
    Map.get(blackboard, :spread_attempts) || 0
  end

  def bump_spread(%__MODULE__{} = blackboard) do
    blackboard
    |> Map.put(:spread_attempts, spread_attempts(blackboard) + 1)
    |> Map.put(:spreading, true)
  end

  def reset_spread(%__MODULE__{} = blackboard) do
    blackboard
    |> Map.put(:spread_attempts, 0)
    |> Map.put(:spreading, false)
  end

  def spreading?(%__MODULE__{} = blackboard) do
    Map.get(blackboard, :spreading) || false
  end

  def mark_spreading(%__MODULE__{} = blackboard) do
    Map.put(blackboard, :spreading, true)
  end

  def clear_spreading(%__MODULE__{} = blackboard) do
    Map.put(blackboard, :spreading, false)
  end

  def clear_attack(%__MODULE__{} = blackboard) do
    %{blackboard | next_attack_at: 0, attack_started: false, auto_attacking: false}
  end

  def reset_spells(%__MODULE__{} = blackboard) do
    blackboard
    |> Map.put(:spell_timers, nil)
    |> Map.put(:next_spell_list_at, 0)
    |> Map.put(:combat_movement, true)
  end

  def combat_movement?(%__MODULE__{} = blackboard) do
    Map.get(blackboard, :combat_movement) != false
  end

  def run_mode?(%__MODULE__{} = blackboard) do
    Map.get(blackboard, :run_mode) == true
  end

  def set_run_mode(%__MODULE__{} = blackboard, enabled) when is_boolean(enabled) do
    Map.put(blackboard, :run_mode, enabled)
  end

  def set_combat_movement(%__MODULE__{} = blackboard, enabled) when is_boolean(enabled) do
    Map.put(blackboard, :combat_movement, enabled)
  end

  def spell_timer_ready?(%__MODULE__{} = blackboard, index, now) when is_integer(index) and is_integer(now) do
    case Map.get(blackboard, :spell_timers) do
      %{^index => ready_at} when is_integer(ready_at) -> now >= ready_at
      _ -> false
    end
  end

  def put_spell_timer(%__MODULE__{} = blackboard, index, delay_ms, now)
      when is_integer(index) and is_integer(delay_ms) and is_integer(now) do
    timers = Map.get(blackboard, :spell_timers) || %{}
    Map.put(blackboard, :spell_timers, Map.put(timers, index, now + delay_ms))
  end

  def fleeing?(%__MODULE__{} = blackboard) do
    is_integer(Map.get(blackboard, :flee_until))
  end

  def start_flee(%__MODULE__{} = blackboard, from_guid, duration_ms, now)
      when is_integer(duration_ms) and is_integer(now) do
    %{blackboard | flee_until: now + duration_ms, flee_from: from_guid}
  end

  def clear_flee(%__MODULE__{} = blackboard) do
    %{blackboard | flee_until: nil, flee_from: nil}
  end

  def clear_attack_started(%__MODULE__{} = blackboard) do
    %{blackboard | attack_started: false}
  end

  def clear_auto_attack(%__MODULE__{} = blackboard) do
    %{blackboard | attack_started: false, auto_attacking: false}
  end

  def enable_auto_attack(%__MODULE__{} = blackboard) do
    %{blackboard | auto_attacking: true}
  end
end
