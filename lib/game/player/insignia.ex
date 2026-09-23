defmodule ThistleTea.Game.Player.Insignia do
  @moduledoc "Routes corpse claims through the victim and corpse owners, then opens the resulting bones."

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Logic.CorpseReclaim
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Insignia
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Corpses
  alias ThistleTea.Game.World.InsigniaTarget

  def complete(%{character: %Character{} = character} = state, targets, spell_id) do
    info = InsigniaTarget.info(character, targets)

    case Insignia.validate(character, info) do
      :ok ->
        case Entity.pid(info.guid) do
          pid when is_pid(pid) -> Entity.remove_insignia(pid, state.guid, info.death_id)
          nil -> claim(info.body_guid, state.guid, info.death_id)
        end

        state

      {:error, reason} ->
        Network.send_packet(Message.SmsgCastResult.failure(spell_id, reason))
        state
    end
  end

  def remove(%{character: %Character{} = character} = state, looter_guid, death_id) do
    with false <- Death.alive?(character),
         true <- character.internal.corpse_reclaim.expires_at == death_id,
         :ok <- validate_unreleased(character, looter_guid) do
      state = Corpses.release(state)

      case claim(Corpse.guid_for(state.guid), looter_guid, death_id) do
        {:ok, _bones} ->
          Network.send_packet(%Message.SmsgPlayerSkinned{})
          Network.send_packet(%Message.MsgCorpseQueryResponse{})
          %{state | character: CorpseReclaim.clear_release(state.character)}

        _failed ->
          state
      end
    else
      _invalid -> state
    end
  end

  defp validate_unreleased(character, looter_guid) do
    if Death.ghost?(character), do: :ok, else: InsigniaTarget.validate_owner(character, looter_guid)
  end

  defp claim(corpse_guid, looter_guid, death_id) do
    case Entity.call(corpse_guid, {:remove_insignia, looter_guid, death_id}) do
      {:ok, bones} = result ->
        Entity.insignia_loot(looter_guid, bones)
        result

      error ->
        error
    end
  end
end
