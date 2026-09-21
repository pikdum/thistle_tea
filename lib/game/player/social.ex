defmodule ThistleTea.Game.Player.Social do
  @moduledoc """
  Player-owner requests for friend and ignore lists, including offline name
  resolution and the vanilla client's ignored-whisper acknowledgment.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgFriendStatus
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Social
  alias ThistleTea.Game.Social.Friend
  alias ThistleTea.Game.Social.Notifier
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.SocialStore

  def send_lists(%Character{object: %{guid: guid}}) do
    social = SocialStore.get(guid)
    send_friends(social)
    Network.send_packet(%Message.SmsgIgnoreList{guids: Enum.sort(social.ignored)}, guid)
  end

  def list(%{ready: true, character: %Character{} = character} = state) do
    character.object.guid |> SocialStore.get() |> send_friends()
    state
  end

  def list(state), do: state

  def add(%{ready: true, guid: guid, character: %Character{} = character} = state, kind, name) do
    target = CharacterStore.get_by_name(String.capitalize(name))
    target_guid = if target, do: target.object.guid, else: 0

    result =
      with :ok <- same_team(kind, character, target),
           {:ok, social} <- Social.add(SocialStore.get(guid), kind, target_guid) do
        SocialStore.put(social)
        :added
      else
        {:error, reason} -> reason
      end

    friend = Notifier.friend(target_guid)
    result = if kind == :friend and result == :added and friend.status != 0, do: :added_online, else: result
    send_result(guid, kind, result, friend)
    state
  end

  def add(state, _kind, _name), do: state

  def remove(%{ready: true, guid: guid} = state, kind, target) do
    guid |> SocialStore.get() |> Social.remove(kind, target) |> SocialStore.put()
    send_result(guid, kind, :removed, %Friend{guid: target})
    state
  end

  def remove(state, _kind, _target), do: state

  def ignored(%{ready: true, guid: guid, character: %Character{} = character} = state, sender) do
    if SocialStore.ignores?(guid, sender) do
      Network.send_packet(
        %Message.SmsgMessagechat{
          chat_type: 0x16,
          language: 0,
          sender_guid: guid,
          message: character.internal.name,
          tag: 0
        },
        sender
      )
    end

    state
  end

  def ignored(state, _sender), do: state

  defp send_friends(%Social{owner_guid: guid, friends: guids}) do
    friends = guids |> Enum.sort() |> Enum.map(&Notifier.friend/1)
    Network.send_packet(%Message.SmsgFriendList{friends: friends}, guid)
  end

  defp send_result(guid, kind, result, friend) do
    Network.send_packet(%SmsgFriendStatus{result: SmsgFriendStatus.code(kind, result), friend: friend}, guid)
  end

  defp same_team(:friend, %Character{unit: %{race: race}}, %Character{unit: %{race: target_race}}) do
    if Party.same_team?(race, target_race), do: :ok, else: {:error, :enemy}
  end

  defp same_team(_kind, _character, _target), do: :ok
end
