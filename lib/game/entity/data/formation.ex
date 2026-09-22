defmodule ThistleTea.Game.Entity.Data.Formation do
  @moduledoc """
  Immutable formation membership projected by the group owner. The optional
  route is supplied only to a temporary leader continuing the original patrol.
  """

  @enforce_keys [:token, :role]
  defstruct [
    :token,
    :role,
    :leader_guid,
    :member,
    :route,
    :last_waypoint,
    :home_position,
    :original_guid,
    :original_spawn
  ]
end
