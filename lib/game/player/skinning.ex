defmodule ThistleTea.Game.Player.Skinning do
  @moduledoc """
  Completes skinning casts through the corpse owner and projects private loot
  and profession gains to the player.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Skinning, as: SkinningLogic
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Looting
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility

  def complete(%{character: %Character{} = character} = state, guid, spell_id) do
    target = Map.put(Metadata.get(guid) || %{}, :guid, guid)
    spell = SpellLoader.load(spell_id)
    count_item = fn id -> Inventory.count_entry(character.player, id, &ItemStore.get/1) end

    with false <- Core.dead?(character),
         true <- Visibility.can_see?(state, guid),
         :ok <- SkinningLogic.validate(character, spell, target, count_item: count_item) do
      state = Looting.release(state)

      case Entity.call(guid, {:skin_corpse, Looting.actor(state, guid), SkinningLogic.skill(character)}) do
        {:ok, loot, level, rank} ->
          character = advance_skill(character, level, rank)
          Network.send_packet(%Message.SmsgLootResponse{guid: guid, loot: loot, loot_type: 2})
          %{state | character: character, loot_guid: guid, loot_type: :skinning}

        {:error, reason} ->
          fail(state, spell_id, reason)

        _ ->
          fail(state, spell_id, :bad_targets)
      end
    else
      {:error, reason} -> fail(state, spell_id, reason)
      _ -> fail(state, spell_id, :bad_targets)
    end
  end

  defp advance_skill(%Character{} = character, level, rank) do
    case SkinningLogic.skill_up(character.player.skills, level, rank, :rand.uniform() * 100) do
      {:gained, skills} ->
        character = %{character | player: %{character.player | skills: skills}}
        CharacterStore.put(character)
        Network.send_packet(Core.update_object(character, :values))
        character

      :unchanged ->
        character
    end
  end

  defp fail(state, spell_id, reason) do
    Network.send_packet(Message.SmsgCastResult.failure(spell_id, reason))
    state
  end
end
