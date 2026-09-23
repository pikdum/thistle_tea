defmodule ThistleTea.Game.Entity.Logic.SafePosition do
  @moduledoc """
  Remembers the last grounded player position for the Stuck spell.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock

  @enforce_keys [:world, :position]
  defstruct [:world, :position]

  @sample_distance_squared 9.0
  @surface_tolerance 3.0

  def needs_update?(%Character{internal: %Internal{} = internal, movement_block: %MovementBlock{} = movement}) do
    grounded?(movement) and moved_from_safe_position?(internal.safe_position, internal.world, movement.position)
  end

  def needs_update?(_character), do: false

  def remember(
        %Character{internal: %Internal{} = internal, movement_block: %MovementBlock{} = movement} = character,
        heights \\ []
      )
      when is_list(heights) do
    if needs_update?(character) and on_surface?(movement.position, heights) do
      safe_position = %__MODULE__{world: internal.world, position: movement.position}
      %{character | internal: %{internal | safe_position: safe_position}}
    else
      character
    end
  end

  def destination(%Character{internal: %Internal{world: world, safe_position: %__MODULE__{world: world} = safe}}),
    do: safe.position

  def destination(_character), do: nil

  defp moved_from_safe_position?(%__MODULE__{world: world, position: {sx, sy, sz, _o}}, world, {x, y, z, _o2}) do
    :math.pow(x - sx, 2) + :math.pow(y - sy, 2) + :math.pow(z - sz, 2) >= @sample_distance_squared
  end

  defp moved_from_safe_position?(_safe, _world, _position), do: true

  defp on_surface?(_position, []), do: true

  defp on_surface?({_x, _y, z, _orientation}, heights) do
    Enum.any?(heights, &(is_number(&1) and abs(&1 - z) <= @surface_tolerance))
  end

  defp grounded?(%MovementBlock{position: {x, y, z, orientation}} = movement)
       when is_number(x) and is_number(y) and is_number(z) and is_number(orientation) do
    not MovementBlock.airborne?(movement) and not MovementBlock.swimming?(movement) and
      not MovementBlock.on_transport?(movement)
  end

  defp grounded?(_movement), do: false
end
