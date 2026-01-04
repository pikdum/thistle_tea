defmodule ThistleTea.Game.Entity.Logic.AI.BT.Blackboard do
  defstruct now: nil,
            target: nil,
            move_target: nil,
            orientation: nil,
            wait_time: nil,
            last_target_pos: nil,
            chase_started: false,
            next_chase_at: 0,
            next_wander_at: 0,
            next_waypoint_at: 0

  def new do
    %__MODULE__{}
  end

  def from_any(%__MODULE__{} = blackboard), do: blackboard
  def from_any(nil), do: new()

  def from_any(%{} = data) do
    struct(__MODULE__, data)
  end

  def with_now(%__MODULE__{} = blackboard, now) when is_integer(now) do
    %{blackboard | now: now}
  end

  def with_now(%__MODULE__{} = blackboard, _now) do
    blackboard
  end

  def now(%__MODULE__{now: now}) when is_integer(now) do
    now
  end

  def now(_blackboard) do
    System.monotonic_time(:millisecond)
  end

  def ready_for?(%__MODULE__{} = blackboard, key) when is_atom(key) do
    case Map.get(blackboard, key) do
      nil -> true
      0 -> true
      ready_at -> System.monotonic_time(:millisecond) >= ready_at
    end
  end

  def delay_until(%__MODULE__{} = blackboard, key) when is_atom(key) do
    now = now(blackboard)

    case Map.get(blackboard, key) do
      nil -> 0
      0 -> 0
      ready_at when is_integer(ready_at) -> max(ready_at - now, 0)
      _ -> 0
    end
  end

  def put_next_at(%__MODULE__{} = blackboard, key, delay_ms) when is_atom(key) and is_integer(delay_ms) do
    Map.put(blackboard, key, System.monotonic_time(:millisecond) + delay_ms)
  end

  def put_next_at(%__MODULE__{} = blackboard, _key, _delay_ms) do
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
end
