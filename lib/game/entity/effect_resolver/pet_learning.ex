defmodule ThistleTea.Game.Entity.EffectResolver.PetLearning do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.PetSpells

  def resolve(entity, effect, opts \\ [])

  def resolve(
        %Mob{internal: %{pet: %Pet{kind: :hunter, owner_guid: owner}}} = pet,
        %Effects.PetAbilityUsed{spell_id: id},
        opts
      ) do
    profile = Keyword.get_lazy(opts, :profile, fn -> PetSpells.profile(Guid.entry(pet.object.guid)) end)
    roll = Keyword.get(opts, :roll, fn -> :rand.uniform(101) - 1 end)

    case Map.get(profile.recipes, id) do
      recipe when is_integer(recipe) ->
        if roll.() < 10 do
          [%Effects.LearnPetRecipe{source_guid: pet.object.guid, target_guid: owner, spell_id: recipe}]
        else
          []
        end

      _ ->
        []
    end
  end

  def resolve(_entity, _effect, _opts), do: []
end
