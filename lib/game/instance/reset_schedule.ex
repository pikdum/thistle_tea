defmodule ThistleTea.Game.Instance.ResetSchedule do
  @moduledoc "UTC raid reset periods shared by every copy of a map during the server lifetime."

  @day 86_400
  @reset_hour 4
  @enforce_keys [:period, :deadline]
  defstruct @enforce_keys

  def new(days, now) when is_integer(days) and days > 0 do
    period = days * @day
    %__MODULE__{period: period, deadline: div(now, @day) * @day + period + @reset_hour * 3_600}
  end

  def advance(%__MODULE__{deadline: deadline, period: period} = schedule, now) when now >= deadline do
    %{schedule | deadline: deadline + (div(now - deadline, period) + 1) * period}
  end

  def advance(%__MODULE__{} = schedule, _now), do: schedule
end
