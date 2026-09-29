defmodule ThistleTea.Game.Core.OutdoorPvp.Participation do
  @moduledoc "Pure player eligibility for presence-based outdoor objectives."

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit

  def eligible?(%Character{player: %Player{}, unit: %Unit{}, internal: %Internal{}} = character, realm) do
    Death.alive?(character) and ((character.player.flags || 0) &&& 0x08) == 0 and
      is_nil(character.internal.taxi_flight) and
      (realm == :pvp or character.internal.pvp.desired?) and
      not Aura.has_aura?(character, :mod_stealth) and not Aura.has_aura?(character, :mod_invisibility)
  end

  def eligible?(_character, _realm), do: false
end
