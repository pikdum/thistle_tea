defmodule ThistleTea.Game.World.Entity.Player.Skinning do
  @moduledoc """
  Completes skinning casts through the corpse owner and projects private loot,
  profession gains, and any spell the corpse makes its skinner cast.
  """
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity, as: EntityCore
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Profession.Skinning, as: SkinningCore
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.Player.Looting
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.Visibility

  def complete(%{character: %Character{} = character} = state, guid, spell_id) do
    target = Map.put(Metadata.get(guid) || %{}, :guid, guid)
    spell = SpellLoader.load(spell_id)
    count_item = fn id -> Inventory.count_entry(character.player, id, &ItemStore.get/1) end

    with false <- EntityCore.dead?(character),
         true <- Visibility.can_see?(state, guid),
         :ok <- SkinningCore.validate(character, spell, target, count_item: count_item) do
      state = Looting.release(state)

      case Entity.call(guid, {:skin_corpse, Looting.actor(state, guid), SkinningCore.skill(character)}) do
        {:ok, loot, level, rank} ->
          character = character |> advance_skill(level, rank) |> cast_corpse_spell(guid)
          Outbound.send_packet(%Message.SmsgLootResponse{guid: guid, loot: loot, loot_type: 2})
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
    case SkinningCore.skill_up(character.player.skills, level, rank, :rand.uniform() * 100) do
      {:gained, skills} ->
        character = %{character | player: %{character.player | skills: skills}}
        CharacterStore.put(character)
        Outbound.send_packet(UpdateObject.from_entity(character, :values))
        character

      :unchanged ->
        character
    end
  end

  defp cast_corpse_spell(%Character{object: %{guid: player_guid}} = character, guid) do
    case SkinningCore.corpse_spell(Guid.entry(guid)) do
      nil -> character
      spell_id -> EventSink.emit(character, Effects.trigger_spell_request(player_guid, spell_id, player_guid, []))
    end
  end

  defp fail(state, spell_id, reason) do
    Outbound.send_packet(Message.SmsgCastResult.failure(spell_id, reason))
    state
  end
end
