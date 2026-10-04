defmodule ThistleTea.Game.Core.GameObject.UseRequirement do
  @moduledoc """
  vmangos `gameobject_requirement`: a spawn players may use only once another
  spawn in the same copy is dead (a creature) or open (an object). A required
  spawn that is not loaded does not block, as in vmangos.
  """

  @enforce_keys [:type, :db_guid]
  defstruct [:type, :db_guid]

  @types %{0 => :dead_creature, 1 => :active_object}
  @go_state_active 0

  def from_row(req_type, db_guid) do
    case Map.fetch(@types, req_type) do
      {:ok, type} -> %__MODULE__{type: type, db_guid: db_guid}
      :error -> nil
    end
  end

  def met?(%__MODULE__{type: :dead_creature}, %{alive?: true}), do: false
  def met?(%__MODULE__{type: :active_object}, %{go_state: state}) when state != @go_state_active, do: false
  def met?(_requirement, _required), do: true
end
