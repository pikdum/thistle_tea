defmodule ThistleTea.Game.Battleground.ControlPoint do
  @moduledoc "Pure contested ownership with timed capture, immediate defense, and stale timer rejection."

  defstruct [:owner, :assaulting, :capture_at, revision: 0]

  def assault(%__MODULE__{assaulting: team} = point, team, _now, _duration), do: {:unchanged, point}
  def assault(%__MODULE__{owner: team, assaulting: nil} = point, team, _now, _duration), do: {:unchanged, point}

  def assault(%__MODULE__{owner: team} = point, team, _now, _duration) when team in [:alliance, :horde] do
    {:defended, %{point | assaulting: nil, capture_at: nil, revision: point.revision + 1}}
  end

  def assault(%__MODULE__{} = point, team, now, duration)
      when team in [:alliance, :horde] and is_integer(now) and is_integer(duration) and duration > 0 do
    {:assaulted, %{point | assaulting: team, capture_at: now + duration, revision: point.revision + 1}}
  end

  def capture(%__MODULE__{revision: revision, assaulting: team, capture_at: deadline} = point, revision, now)
      when team in [:alliance, :horde] and is_integer(deadline) and now >= deadline do
    {:captured, %{point | owner: team, assaulting: nil, capture_at: nil, revision: revision + 1}}
  end

  def capture(%__MODULE__{} = point, _revision, _now), do: {:unchanged, point}

  def controlled_by(%__MODULE__{assaulting: nil, owner: owner}), do: owner
  def controlled_by(%__MODULE__{}), do: nil

  def state(%__MODULE__{assaulting: :alliance}), do: 1
  def state(%__MODULE__{assaulting: :horde}), do: 2
  def state(%__MODULE__{owner: :alliance}), do: 3
  def state(%__MODULE__{owner: :horde}), do: 4
  def state(%__MODULE__{}), do: 0
end
