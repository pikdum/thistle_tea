defmodule ThistleTea.Game.World.Entity.Player.PetExperience do
  @moduledoc """
  Forwards eligible kill rewards to the player's current hunter pet owner.
  Solo rewards use the owner's base reward and the pet's victim-level factor.
  Group rewards use the owner's level-weighted share and check the pet's level
  independently of the owner's XP eligibility.
  """

  alias ThistleTea.Game.Core.Combat.KillCredit
  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.World.Combat.KillReward
  alias ThistleTea.Game.World.Entity

  def reward_kill(%Character{} = character, %Mob{internal: %Internal{creature: %Creature{}}} = victim, xp, mode)
      when is_integer(xp) and xp > 0 do
    with true <- KillCredit.eligible?(victim),
         true <- Death.alive?(character),
         %{kind: :hunter_pet} <- Companion.relationship(character),
         pid when is_pid(pid) <- Entity.pid(Companion.active_guid(character)) do
      reward =
        case mode do
          :solo ->
            {:solo, victim.unit.level, KillReward.experience_options(victim)}

          {:group, max_level} ->
            {:group, xp, max_level}
        end

      send(pid, {:reward_pet_kill, character.object.guid, character.unit.level, reward})
    end

    :ok
  end

  def reward_kill(_character, _victim, _xp, _mode), do: :ok
end
