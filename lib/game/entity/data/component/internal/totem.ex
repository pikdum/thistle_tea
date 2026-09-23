defmodule ThistleTea.Game.Entity.Data.Component.Internal.Totem do
  @moduledoc false

  defstruct [:owner_guid, :expires_at, passive_spell_started?: false]
end
