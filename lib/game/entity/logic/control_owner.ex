defmodule ThistleTea.Game.Entity.Logic.ControlOwner do
  @moduledoc "Resolves the current charmer, companion owner, or actor for outgoing combat snapshots."

  def guid(%{unit: %{charmed_by: guid}}) when is_integer(guid) and guid > 0, do: guid
  def guid(%{internal: %{possession: %{caster_guid: guid}}}) when is_integer(guid) and guid > 0, do: guid
  def guid(%{internal: %{pet: %{owner_guid: guid}}}) when is_integer(guid) and guid > 0, do: guid
  def guid(%{internal: %{totem: %{owner_guid: guid}}}) when is_integer(guid) and guid > 0, do: guid
  def guid(%{object: %{guid: guid}}) when is_integer(guid), do: guid
  def guid(_entity), do: nil
end
