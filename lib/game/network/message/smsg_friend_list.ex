defmodule ThistleTea.Game.Network.Message.SmsgFriendList do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_FRIEND_LIST

  alias ThistleTea.Game.Social.Friend

  defstruct friends: []

  @impl ServerMessage
  def to_binary(%__MODULE__{friends: friends}) do
    IO.iodata_to_binary([<<length(friends)>> | Enum.map(friends, &friend_binary/1)])
  end

  def friend_binary(%Friend{guid: guid, status: 0}), do: <<guid::little-size(64), 0>>

  def friend_binary(%Friend{guid: guid, status: status, zone: zone, level: level, class: class}) do
    <<guid::little-size(64), status, zone::little-size(32), level::little-size(32), class::little-size(32)>>
  end
end
