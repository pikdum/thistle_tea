defmodule ThistleTea.Game.Player.Groups do
  @moduledoc """
  Player-owner requests for raid management, target markers, and ready checks.
  Membership mutations are serialized by the party system before projection.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgPartyCommandResult, as: Result
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Party.Member
  alias ThistleTea.Game.Party.Notifier
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SocialStore
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  def invite(%{ready: true, guid: guid, character: %Character{} = character} = state, name) do
    name = String.capitalize(name)
    invitee_guid = Metadata.find_guid_by(:name, name)

    result =
      cond do
        invitee_guid == nil or invitee_guid == guid -> {:error, :bad_player_name}
        not same_team?(character.unit.race, invitee_guid) -> {:error, :wrong_faction}
        SocialStore.ignores?(invitee_guid, guid) -> {:error, :ignoring_you}
        true -> PartySystem.invite(guid, character.internal.name, invitee_guid)
      end

    reason =
      case result do
        :ok ->
          Network.send_packet(%Message.SmsgGroupInvite{name: character.internal.name}, invitee_guid)
          :ok

        {:error, reason} ->
          reason
      end

    Network.send_packet(%Result{operation: Result.op_invite(), name: name, result: Result.code(reason)}, guid)
    state
  end

  def invite(state, _name), do: state

  def convert_raid(%{ready: true, guid: guid, character: %Character{} = character} = state) do
    if !MapTemplate.battleground?(character.internal.world.map_id) do
      with {:ok, group} <- PartySystem.convert_raid(guid) do
        Network.send_packet(%Result{operation: Result.op_invite(), name: "", result: Result.code(:ok)}, guid)
        Notifier.send_group_list(group)
      end
    end

    state
  end

  def convert_raid(state), do: state

  def change_subgroup(%{ready: true, guid: guid} = state, name, subgroup) do
    with %Member{guid: target} <- named_member(guid, name),
         {:ok, group} <- PartySystem.change_subgroup(guid, target, subgroup) do
      Notifier.send_group_list(group)
    end

    state
  end

  def change_subgroup(state, _name, _subgroup), do: state

  def swap_subgroups(%{ready: true, guid: guid} = state, first_name, second_name) do
    with %Member{guid: first} <- named_member(guid, first_name),
         %Member{guid: second} <- named_member(guid, second_name),
         {:ok, group} <- PartySystem.swap_subgroups(guid, first, second) do
      Notifier.send_group_list(group)
    end

    state
  end

  def swap_subgroups(state, _first, _second), do: state

  def set_assistant(%{ready: true, guid: guid} = state, target, enabled?) do
    with pid when is_pid(pid) <- Entity.pid(target),
         {:ok, group} <- PartySystem.set_assistant(guid, target, enabled?) do
      Notifier.send_group_list(group)
    end

    state
  end

  def set_assistant(state, _target, _enabled?), do: state

  def target_icon(%{ready: true, guid: guid} = state, 0xFF, _target) do
    with %Group{} = group <- PartySystem.group_of(guid) do
      Network.send_packet(%Message.MsgRaidTargetUpdateResponse{icons: Enum.sort(group.icons)}, guid)
    end

    state
  end

  def target_icon(%{ready: true, guid: guid} = state, icon, target) do
    with {:ok, group, changes} <- PartySystem.set_icon(guid, icon, target) do
      Enum.each(changes, fn {id, target} ->
        Notifier.broadcast(group, %Message.MsgRaidTargetUpdateResponse{icon: id, target: target})
      end)
    end

    state
  end

  def target_icon(state, _icon, _target), do: state

  def ready_check(%{ready: true, guid: guid} = state, nil) do
    with %Group{} = group <- PartySystem.group_of(guid),
         true <- Party.manager?(group, guid) do
      Notifier.broadcast(group, %Message.MsgRaidReadyCheckResponse{})

      Enum.each(group.members, &report_offline_member(&1, group.leader))
    end

    state
  end

  def ready_check(%{ready: true, guid: guid} = state, ready?) when is_boolean(ready?) do
    with %Group{} = group <- PartySystem.group_of(guid) do
      Network.send_packet(%Message.MsgRaidReadyCheckResponse{guid: guid, ready?: ready?}, group.leader)
    end

    state
  end

  def ready_check(state, _ready?), do: state

  defp report_offline_member(%Member{guid: guid}, leader) do
    if !Entity.online?(guid) do
      Network.send_packet(%Message.MsgRaidReadyCheckResponse{guid: guid, ready?: false}, leader)
    end
  end

  defp named_member(guid, name) do
    with %Group{} = group <- PartySystem.group_of(guid), do: Party.member_by_name(group, name)
  end

  defp same_team?(race, invitee_guid) do
    case Metadata.query(invitee_guid, [:race]) do
      %{race: target_race} when is_integer(target_race) -> Party.same_team?(race, target_race)
      _ -> false
    end
  end
end
