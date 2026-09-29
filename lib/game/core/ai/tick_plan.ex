defmodule ThistleTea.Game.Core.AI.TickPlan do
  @moduledoc """
  A typed set of behavior-runtime wake deadlines.

  Systems contribute absolute deadlines with a semantic source. The owning
  process schedules only the earliest wake, so adding maintenance work does
  not require threading delay calculations through behavior-tree branches.
  A dormant plan with no wakes has no next wake at all: the owner sleeps until
  a message arrives instead of falling back to the default cadence.
  """

  defmodule Wake do
    @moduledoc false
    @enforce_keys [:at, :source]
    defstruct [:at, :source]
  end

  @enforce_keys [:now]
  defstruct [:now, wakes: [], dormant?: false]

  def new(now) when is_integer(now), do: %__MODULE__{now: now}

  def schedule_in(%__MODULE__{} = plan, source, delay_ms)
      when is_atom(source) and is_integer(delay_ms) and delay_ms >= 0 do
    schedule_at(plan, source, plan.now + delay_ms)
  end

  def schedule_in(%__MODULE__{} = plan, _source, _delay_ms), do: plan

  def schedule_at(%__MODULE__{} = plan, source, at) when is_atom(source) and is_integer(at) do
    %{plan | wakes: [%Wake{at: at, source: source} | plan.wakes]}
  end

  def dormant(%__MODULE__{} = plan), do: %{plan | dormant?: true}

  def next(plan, fallback_ms \\ 100)

  def next(%__MODULE__{wakes: [], dormant?: true}, _fallback_ms), do: nil

  def next(%__MODULE__{wakes: []} = plan, fallback_ms) when is_integer(fallback_ms) and fallback_ms >= 0 do
    %Wake{at: plan.now + fallback_ms, source: :default}
  end

  def next(%__MODULE__{wakes: wakes}, _fallback_ms) do
    Enum.min_by(wakes, & &1.at)
  end

  def delay(%__MODULE__{} = plan, fallback_ms \\ 100) do
    case next(plan, fallback_ms) do
      %Wake{at: at} -> max(at - plan.now, 0)
      nil -> nil
    end
  end
end
