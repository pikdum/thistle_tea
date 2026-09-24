defmodule ThistleTea.Game.OutdoorPvp.CapturePoint do
  @moduledoc """
  Pure presence-based capture meter. Signed progress is stored in thousandths
  of a reference capture unit, so elapsed milliseconds do not lose fractional
  progress. Ownership begins beyond the neutral band and ends on reentry.
  """

  alias ThistleTea.Game.OutdoorPvp.CapturePoint.Template

  @enforce_keys [:template]
  defstruct [:template, progress: 0, difference: 0, phase: :neutral]

  def new(%Template{} = template), do: %__MODULE__{template: template}

  def advance(%__MODULE__{} = point, alliance, horde, elapsed_ms)
      when is_integer(alliance) and alliance >= 0 and is_integer(horde) and horde >= 0 and is_integer(elapsed_ms) and
             elapsed_ms > 0 do
    difference = alliance - horde
    maximum = point.template.max_time * 1000
    ceiling = div(maximum * elapsed_ms, point.template.min_time)
    shift = (difference * elapsed_ms) |> max(-ceiling) |> min(ceiling)
    progress = (point.progress + shift) |> max(-maximum) |> min(maximum)
    neutral = div(maximum * point.template.neutral_percent, 100)

    %{point | progress: progress, difference: difference, phase: phase(progress, maximum, neutral, difference)}
  end

  def advance(%__MODULE__{} = point, _alliance, _horde, 0), do: point

  def owner(%__MODULE__{phase: {phase, team}}) when phase in [:progress, :controlled], do: team
  def owner(%__MODULE__{}), do: nil

  def slider(%__MODULE__{template: %Template{max_time: maximum}, progress: progress}) do
    denominator = maximum * 2000
    numerator = (progress + maximum * 1000) * 100
    div(numerator + denominator - 1, denominator)
  end

  def slider_changed?(%__MODULE__{} = previous, %__MODULE__{} = current) do
    slider(previous) != slider(current) or previous.phase != current.phase or
      (previous.difference != 0 and current.difference == 0)
  end

  def enter_states(%__MODULE__{template: template} = point) do
    [{template.display_state, 1}, {template.neutral_state, template.neutral_percent}, position_state(point)]
  end

  def leave_states(%__MODULE__{template: template}), do: [{template.display_state, 0}]
  def position_state(%__MODULE__{template: template} = point), do: {template.position_state, slider(point)}

  defp phase(progress, maximum, _neutral, _difference) when progress == maximum, do: {:controlled, :alliance}
  defp phase(progress, maximum, _neutral, _difference) when progress == -maximum, do: {:controlled, :horde}

  defp phase(progress, _maximum, neutral, _difference) when progress > 0 and progress >= neutral,
    do: {:progress, :alliance}

  defp phase(progress, _maximum, neutral, _difference) when progress < 0 and progress <= -neutral,
    do: {:progress, :horde}

  defp phase(_progress, _maximum, _neutral, difference) when difference > 0, do: {:contested, :alliance}
  defp phase(_progress, _maximum, _neutral, difference) when difference < 0, do: {:contested, :horde}
  defp phase(_progress, _maximum, _neutral, _difference), do: :neutral
end
