defmodule ThistleTea.Game.WorldRef do
  @moduledoc """
  Canonical identity for an isolated copy of a client map.

  The open world uses a nil instance id. Instanced maps share their client
  map id and navigation geometry while remaining isolated by instance id.
  """

  @enforce_keys [:map_id]
  defstruct [:map_id, :instance_id]

  def open(map_id) when is_integer(map_id), do: %__MODULE__{map_id: map_id}

  def instance(map_id, instance_id) when is_integer(map_id) and is_integer(instance_id) do
    %__MODULE__{map_id: map_id, instance_id: instance_id}
  end

  def coerce(%__MODULE__{} = world), do: world
  def coerce(map_id) when is_integer(map_id), do: open(map_id)

  def map_id(%__MODULE__{map_id: map_id}), do: map_id
  def map_id(map_id) when is_integer(map_id), do: map_id

  def open?(%__MODULE__{instance_id: nil}), do: true
  def open?(%__MODULE__{}), do: false
end
