defmodule ThistleTea.Game.Player.QuestSharing do
  @moduledoc """
  Player-owned quest offers, recipient validation, and session-bound acceptance.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestSharing, as: Sharing
  alias ThistleTea.Game.Entity.Logic.QuestSharing.Offer
  alias ThistleTea.Game.Entity.Registry
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  def share(%{ready: true, character: %Character{} = character} = state, quest_id) do
    with %Quest{} = quest <- QuestLoader.get(quest_id),
         true <- Sharing.shareable?(quest, character.player.quest_log, Time.now()) do
      offer_members(state, quest, :manual)
    end

    state
  end

  def share(state, _quest_id), do: state

  def party_accept(%{character: %Character{}} = state, %Quest{} = quest) do
    if Quest.party_accept?(quest), do: offer_members(state, quest, :party_accept)
    state
  end

  def receive_offer(%{ready: true, character: %Character{}} = state, sharer, quest_id, mode)
      when mode in [:manual, :party_accept] do
    state = refresh(state)

    with %Quest{} = quest <- QuestLoader.get(quest_id),
         %Character{} = source <- CharacterStore.get(sharer),
         pid when is_pid(pid) <- Registry.whereis(sharer),
         %Group{} = group <- shared_group(state.guid, sharer),
         true <- source_eligible?(quest, source, mode) do
      offer = %Offer{sharer_guid: sharer, sharer_pid: pid, quest_id: quest_id, group_id: group.id, mode: mode}
      receive_valid_offer(state, quest, offer)
    else
      _invalid -> state
    end
  end

  def receive_offer(state, _sharer, _quest_id, _mode), do: state

  def accept(%{quest_share: %Offer{sharer_guid: sharer, quest_id: quest_id, mode: :manual}} = state, sharer, quest_id) do
    accept_offer(state)
  end

  def accept(state, _sharer, _quest_id), do: state

  def confirm(%{quest_share: %Offer{quest_id: quest_id, mode: :party_accept}} = state, quest_id) do
    accept_offer(state)
  end

  def confirm(state, _quest_id), do: state

  def result(%{ready: true, quest_share: %Offer{} = offer} = state, result) when result in [1, 3, 4, 5, 6, 7, 8] do
    if match?({:ok, _, _}, source(state.guid, offer)), do: send_result(offer.sharer_guid, state.guid, result)
    clear(state)
  end

  def result(state, _result), do: state

  def cancel(%{quest_share: %Offer{sharer_guid: sharer, quest_id: quest_id}} = state, sharer, quest_id) do
    close(state)
  end

  def cancel(state, _sharer, _quest_id), do: state

  def refresh(%{quest_share: %Offer{} = offer} = state) do
    case source(state.guid, offer) do
      {:ok, _quest, _character} -> state
      _invalid -> close(state)
    end
  end

  def refresh(state), do: state

  def clear(%{quest_share: %Offer{}} = state) do
    if is_reference(state.quest_share_monitor), do: Process.demonitor(state.quest_share_monitor, [:flush])
    %{state | quest_share: nil, quest_share_monitor: nil}
  end

  def clear(state), do: state

  def close(%{quest_share: %Offer{}} = state) do
    Network.send_packet(%Message.SmsgGossipComplete{}, state.guid)
    clear(state)
  end

  def close(state), do: state

  def disconnect(%{character: %Character{} = character} = state) do
    for entry <- QuestLog.active_entries(character.player.quest_log) do
      cancel_members(character.object.guid, entry.quest_id)
    end

    clear(state)
  end

  def disconnect(state), do: state

  def quest_log_changed(%Character{} = previous, %Character{} = current) do
    for entry <- QuestLog.active_entries(previous.player.quest_log),
        not Sharing.current?(current.player.quest_log, entry.quest_id, Time.now()) do
      cancel_members(current.object.guid, entry.quest_id)
    end
  end

  defp offer_members(state, quest, mode) do
    for guid <- members(state.guid), guid != state.guid, Entity.online?(guid) do
      Entity.offer_quest(guid, state.guid, quest.id, mode)
    end
  end

  defp cancel_members(sharer, quest_id) do
    for guid <- members(sharer), guid != sharer do
      Entity.cancel_quest_share(guid, sharer, quest_id)
    end
  end

  defp members(guid) do
    case PartySystem.group_of(guid) do
      %Group{members: members} -> Enum.map(members, & &1.guid)
      _group -> []
    end
  end

  defp receive_valid_offer(state, quest, %Offer{mode: :manual} = offer) do
    send_result(offer.sharer_guid, state.guid, :sharing)

    case eligibility(state, quest, near?(state.guid, offer.sharer_guid), not is_nil(state.quest_share)) do
      :ok ->
        present(state, quest, offer)

      result ->
        send_result(offer.sharer_guid, state.guid, result)
        state
    end
  end

  defp receive_valid_offer(state, quest, %Offer{mode: :party_accept} = offer) do
    with true <- confirmation_group?(state.guid, offer.sharer_guid, quest),
         true <- same_world?(state.guid, offer.sharer_guid),
         :ok <- eligibility(state, quest, true, not is_nil(state.quest_share)) do
      present(state, quest, offer)
    else
      _invalid -> state
    end
  end

  defp present(state, quest, %Offer{} = offer) do
    case offer.mode do
      :manual ->
        Network.send_packet(%Message.SmsgQuestgiverQuestDetails{npc_guid: offer.sharer_guid, quest: quest}, state.guid)

      :party_accept ->
        Network.send_packet(%Message.SmsgGossipComplete{}, state.guid)

        Network.send_packet(
          %Message.SmsgQuestConfirmAccept{quest_id: quest.id, title: quest.title, sharer_guid: offer.sharer_guid},
          state.guid
        )
    end

    %{state | quest_share: offer, quest_share_monitor: Process.monitor(offer.sharer_pid)}
  end

  defp accept_offer(%{ready: true, quest_share: %Offer{} = offer} = state) do
    with {:ok, quest, source} <- source(state.guid, offer),
         :ok <- acceptance_eligibility(state, quest, offer) do
      state = clear(state)
      source_guid = if offer.mode == :manual, do: offer.sharer_guid
      source_entry = if offer.mode == :manual, do: QuestLog.get(source.player.quest_log, quest.id)
      accepted = Quests.force_accept(state, quest.id, source_guid, shared_entry: source_entry)

      if QuestLog.active?(accepted.character.player.quest_log, quest.id) do
        Network.send_packet(%Message.SmsgGossipComplete{}, state.guid)
        accepted(accepted, quest, offer)
      else
        send_result(offer.sharer_guid, state.guid, :cannot_take)
        accepted
      end
    else
      {:error, result} ->
        send_result(offer.sharer_guid, state.guid, result)
        close(state)
    end
  end

  defp accept_offer(state), do: state

  defp accepted(state, quest, %Offer{mode: :manual, sharer_guid: sharer}) do
    send_result(sharer, state.guid, :accepted)
    party_accept(state, quest)
  end

  defp accepted(state, _quest, %Offer{mode: :party_accept}), do: state

  defp acceptance_eligibility(state, quest, offer) do
    near? = offer.mode == :party_accept or near?(state.guid, offer.sharer_guid)

    case eligibility(state, quest, near?, false) do
      :ok -> :ok
      result -> {:error, result}
    end
  end

  defp eligibility(state, quest, near?, busy?) do
    availability = Quests.availability(state.character, [quest])
    condition = Map.get(availability.condition_results, quest.id)
    Sharing.offer_result(quest, availability.quest_context, condition, near?, busy?)
  end

  defp source(recipient, %Offer{} = offer) do
    with %Quest{} = quest <- QuestLoader.get(offer.quest_id),
         %Character{} = character <- CharacterStore.get(offer.sharer_guid),
         true <- Registry.whereis(offer.sharer_guid) == offer.sharer_pid,
         %Group{id: group_id} when group_id == offer.group_id <- shared_group(recipient, offer.sharer_guid),
         true <- source_eligible?(quest, character, offer.mode),
         true <- same_world?(recipient, offer.sharer_guid),
         true <- offer.mode == :manual or confirmation_group?(recipient, offer.sharer_guid, quest) do
      {:ok, quest, character}
    else
      _invalid -> {:error, :cannot_take}
    end
  end

  defp source_eligible?(quest, character, :manual) do
    Sharing.shareable?(quest, character.player.quest_log, Time.now())
  end

  defp source_eligible?(quest, character, :party_accept) do
    Quest.party_accept?(quest) and Sharing.current?(character.player.quest_log, quest.id, Time.now())
  end

  defp shared_group(recipient, sharer) when recipient != sharer do
    case PartySystem.group_of(recipient) do
      %Group{} = group -> if Party.member(group, sharer), do: group
      _group -> nil
    end
  end

  defp shared_group(_recipient, _sharer), do: nil

  defp confirmation_group?(recipient, sharer, quest) do
    case shared_group(recipient, sharer) do
      %Group{} = group ->
        Quest.allowed_in_raid?(quest) or Enum.any?(Party.subgroup_members(group, sharer), &(&1.guid == recipient))

      _group ->
        false
    end
  end

  defp same_world?(recipient, sharer) do
    case {World.position(recipient), World.position(sharer)} do
      {{world, _, _, _}, {world, _, _, _}} -> true
      _positions -> false
    end
  end

  defp near?(recipient, sharer) do
    case {World.position(recipient), World.position(sharer)} do
      {{world, x, y, z}, {world, sx, sy, sz}} -> (x - sx) ** 2 + (y - sy) ** 2 + (z - sz) ** 2 < 14.0 ** 2
      _positions -> false
    end
  end

  defp send_result(sharer, recipient, result) do
    Network.send_packet(
      %Message.MsgQuestPushResult{guid: recipient, result: Message.MsgQuestPushResult.code(result)},
      sharer
    )
  end
end
