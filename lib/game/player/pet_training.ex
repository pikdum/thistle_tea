defmodule ThistleTea.Game.Player.PetTraining do
  @moduledoc """
  Routes pet training to the active pet owner and projects a committed purchase.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PetTraining, as: Training
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Spells
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.PetSpells

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
        companion = %{Companion.relationship(character) | autocast: control.autocast}
        character = %{character | internal: %{character.internal | companion: companion}}
        Network.send_packet(Message.SmsgPetSpells.for_pet(effect.target_guid, spells, control))
        %{state | character: character}

      {:error, reason} ->
        Network.send_packet(Message.SmsgCastResult.failure(effect.spell.id, reason))
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
