defmodule ThistleTea.Game.Player.PetExperience do
  @moduledoc """
  Forwards eligible kill rewards to the player's current hunter pet owner.
  Solo rewards use the pet's level; group rewards retain the owner's share.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Experience

  def reward_kill(
        %Character{unit: %Unit{health: health}} = character,
        %Mob{internal: %Internal{pet: nil, creature: %Creature{} = creature}} = victim,
        xp,
        mode
      )
      when health > 0 and is_integer(xp) and xp > 0 do
    with %{kind: :hunter_pet} <- Companion.relationship(character),
         pid when is_pid(pid) <- Entity.pid(Companion.active_guid(character)) do
      reward =
        if mode == :solo do
          {:solo, victim.unit.level,
           [
             experience_multiplier: creature.experience_multiplier,
             extra_flags: creature.extra_flags,
             elite?: Experience.elite_rank?(creature.rank)
           ]}
        else
          {:group, xp}
        end

      send(pid, {:reward_pet_kill, character.object.guid, character.unit.level, reward})
    end

    :ok
  end

  def reward_kill(_character, _victim, _xp, _mode), do: :ok
end
