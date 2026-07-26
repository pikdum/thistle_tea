defmodule ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception do
  @moduledoc """
  Read-only world perception exposed to behavior-tree nodes for one tick.
  """

  @enforce_keys [
    :position,
    :grounded_position,
    :projected_position,
    :distance,
    :moving?,
    :metadata,
    :nearby,
    :line_of_sight?
  ]
  defstruct [
    :position,
    :grounded_position,
    :projected_position,
    :distance,
    :moving?,
    :metadata,
    :nearby,
    :line_of_sight?
  ]

  def empty do
    %__MODULE__{
      position: fn _guid -> nil end,
      grounded_position: fn _guid -> nil end,
      projected_position: fn _guid, _horizon_ms -> nil end,
      distance: fn _guid -> nil end,
      moving?: fn _guid -> false end,
      metadata: fn _guid -> nil end,
      nearby: fn _kind, _radius -> [] end,
      line_of_sight?: fn _guid -> true end
    }
  end

  def position(%__MODULE__{position: position}, guid), do: position.(guid)

  def grounded_position(%__MODULE__{grounded_position: grounded_position}, guid) do
    grounded_position.(guid)
  end

  def projected_position(%__MODULE__{projected_position: projected_position}, guid, horizon_ms) do
    projected_position.(guid, horizon_ms)
  end

  def distance(%__MODULE__{distance: distance}, guid), do: distance.(guid)
  def moving?(%__MODULE__{moving?: moving?}, guid), do: moving?.(guid)
  def metadata(%__MODULE__{metadata: metadata}, guid), do: metadata.(guid)
  def nearby(%__MODULE__{nearby: nearby}, kind, radius), do: nearby.(kind, radius)
  def line_of_sight?(%__MODULE__{line_of_sight?: line_of_sight?}, guid), do: line_of_sight?.(guid)
end
