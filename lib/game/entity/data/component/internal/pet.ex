defmodule ThistleTea.Game.Entity.Data.Component.Internal.Pet do
  @moduledoc """
  Runtime ownership and command state shared by combat pets, guardians, and
  non-combat companions.
  """

  defstruct [
    :owner_guid,
    :profile,
    :stay_position,
    action_bar: %{},
    command_state: :follow,
    reaction_state: :defensive,
    autocast: MapSet.new()
  ]
end
