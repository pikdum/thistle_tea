defmodule ThistleTea.Game.OutdoorPvp.Participation do
  @moduledoc "Pure player eligibility for presence-based outdoor objectives."

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Death

  def eligible?(%Character{} = character, realm) do
    Death.alive?(character) and ((character.player.flags || 0) &&& 0x08) == 0 and
      is_nil(character.internal.taxi_flight) and
      (realm == :pvp or character.internal.pvp.desired?) and
      not Aura.has_aura?(character, :mod_stealth) and not Aura.has_aura?(character, :mod_invisibility)
  end
end
