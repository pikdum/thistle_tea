defmodule ThistleTea.Game.Entity.Logic.TargetRef do
  @moduledoc """
  Identifies one lifetime of an entity whose stable GUID may be reused.
  """

  @enforce_keys [:guid]
  defstruct [:guid, :incarnation_id]

  def new(guid, metadata \\ %{}) when is_integer(guid) and is_map(metadata) do
    %__MODULE__{guid: guid, incarnation_id: Map.get(metadata, :incarnation_id)}
  end

  def active?(%__MODULE__{incarnation_id: incarnation_id}, %{alive?: true, incarnation_id: incarnation_id})
      when is_integer(incarnation_id) do
    true
  end

  def active?(%__MODULE__{incarnation_id: nil}, %{alive?: true}), do: true
  def active?(%__MODULE__{}, _metadata), do: false
end
