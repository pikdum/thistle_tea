defmodule ThistleTea.Game.World.Entity.Player.PetTraining do
  @moduledoc """
  Routes pet training to the active pet owner and projects a committed purchase.
  """

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.PetTraining, as: Training
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.Spells
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Loader.PetSpells
  alias ThistleTea.Game.World.Outbound

  def discover(%State{character: %Character{} = character} = state, %Effects.LearnPetRecipe{} = effect) do
    if effect.target_guid == character.object.guid and Companion.summon_guid(character) == effect.source_guid do
      %{state | character: learn_recipes(character, [effect.spell_id])}
    else
      state
    end
  end

  def discover(state, _effect), do: state

  def discover_passives(%State{character: %Character{} = character} = state, %{
        kind: :hunter_pet,
        entity_ref: ref,
        spells: spells
      }) do
    profile = PetSpells.profile(ref.entry)

    recipes =
      spells
      |> Enum.filter(&Spell.attribute?(&1, :passive))
      |> Enum.flat_map(fn spell ->
        case Map.get(profile.recipes, spell.id) do
          id when is_integer(id) -> [id]
          _ -> []
        end
      end)

    %{state | character: learn_recipes(character, recipes)}
  end

  def discover_passives(state, _attachment), do: state

  defp learn_recipes(character, []), do: character

  defp learn_recipes(character, recipes) do
    unknown = recipes -- (character.internal.spells || [])
    learn_unknown_recipes(character, unknown)
  end

  defp learn_unknown_recipes(character, []), do: character

  defp learn_unknown_recipes(character, recipes) do
    case Spells.learn(character, recipes) do
      {:ok, character, _events} -> character
      :already_known -> character
    end
  end

  def validate(%Character{} = character, %Spell{} = spell) do
    if Training.ability_id(spell) do
      request(character, :validate_pet_training, Companion.summon_guid(character), spell)
    else
      :ok
    end
  end

  def learn(%State{character: %Character{} = character} = state, %Effects.LearnPetSpell{} = effect) do
    case request(character, :learn_pet_spell, effect.target_guid, effect.spell) do
      {:ok, spells, control} ->
        character = Companion.remember_controls(character, effect.target_guid, control)
        Outbound.send_packet(Message.SmsgPetSpells.for_pet(effect.target_guid, spells, control))
        %{state | character: character}

      {:error, reason} ->
        Outbound.send_packet(Message.SmsgCastResult.failure(effect.spell.id, reason))
        state
    end
  end

  def learn(state, _effect), do: state

  defp request(character, command, guid, spell) when is_integer(guid) do
    if Companion.summon_guid(character) == guid do
      case Entity.call(guid, {command, character.object.guid, spell}) do
        {:error, :not_found} -> {:error, :no_pet}
        result -> result
      end
    else
      {:error, :no_pet}
    end
  end

  defp request(_character, _command, _guid, _spell), do: {:error, :no_pet}
end
