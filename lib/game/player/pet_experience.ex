defmodule ThistleTea.Game.Player.PetExperience do
  @moduledoc """
  Forwards eligible kill rewards to the player's current hunter pet owner.
  Solo rewards use the pet's level. Group rewards use the owner's level-weighted
  share and check the pet's level independently of the owner's XP eligibility.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.KillReward
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Death

  def reward_kill(
        %Character{} = character,
        %Mob{internal: %Internal{pet: nil, creature: %Creature{}}} = victim,
        xp,
        mode
      )
      when is_integer(xp) and xp > 0 do
    with true <- Death.alive?(character),
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
