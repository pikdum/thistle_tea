defmodule ThistleTea.Game.Social.Notifier do
  @moduledoc """
  Builds social presence from the live metadata projection and notifies online
  characters who have the subject on their friend list.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.ChatStatus
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message.SmsgFriendStatus
  alias ThistleTea.Game.Social.Friend
  alias ThistleTea.Game.World.Loader.Exploration
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SocialStore

  def friend(guid) do
    if Entity.online?(guid) do
      from_metadata(guid, Metadata.query(guid, [:area, :level, :class, :chat_status]))
    else
      %Friend{guid: guid}
    end
  end

  def online(guid), do: notify(guid, %SmsgFriendStatus{result: 2, friend: friend(guid)})
  def offline(guid), do: notify(guid, %SmsgFriendStatus{result: 3, friend: %Friend{guid: guid}})

  defp notify(guid, packet) do
    guid
    |> SocialStore.followers()
    |> Enum.filter(&Entity.online?/1)
    |> Enum.each(&Network.send_packet(packet, &1))
  end

  defp from_metadata(guid, %{area: area, level: level, class: class} = metadata) do
    %Friend{guid: guid, status: status(Map.get(metadata, :chat_status)), zone: zone(area), level: level, class: class}
  end

  defp from_metadata(guid, _metadata), do: %Friend{guid: guid}

  defp status(%ChatStatus{mode: :afk}), do: 2
  defp status(%ChatStatus{mode: :dnd}), do: 4
  defp status(_status), do: 1

  defp zone(area) do
    case Exploration.area(area) do
      %{parent_area_table: parent} when is_integer(parent) and parent > 0 -> parent
      _ -> area || 0
    end
  end
end
