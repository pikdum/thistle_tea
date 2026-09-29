defmodule ThistleTea.Game.Core.Entity.Component.Internal.Duel do
  @moduledoc false

  defstruct [
    :initiator_guid,
    :opponent_guid,
    :arbiter_guid,
    :started_at,
    state: :requested
  ]
end
