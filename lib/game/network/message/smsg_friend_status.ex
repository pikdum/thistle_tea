defmodule ThistleTea.Game.Network.Message.SmsgFriendStatus do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_FRIEND_STATUS

  alias ThistleTea.Game.Social.Friend

  defstruct [:result, :friend]

  def code(:friend, :full), do: 0x01
  def code(:friend, :not_found), do: 0x04
  def code(:friend, :removed), do: 0x05
  def code(:friend, :added_online), do: 0x06
  def code(:friend, :added), do: 0x07
  def code(:friend, :already), do: 0x08
  def code(:friend, :self), do: 0x09
  def code(:friend, :enemy), do: 0x0A
  def code(:ignore, :full), do: 0x0B
  def code(:ignore, :self), do: 0x0C
  def code(:ignore, :not_found), do: 0x0D
  def code(:ignore, :already), do: 0x0E
  def code(:ignore, :added), do: 0x0F
  def code(:ignore, :removed), do: 0x10

  @impl ServerMessage
  def to_binary(%__MODULE__{result: result, friend: %Friend{} = friend}) when result in [2, 6] do
    <<result, friend.guid::little-size(64), friend.status, friend.zone::little-size(32), friend.level::little-size(32),
      friend.class::little-size(32)>>
  end

  def to_binary(%__MODULE__{result: result, friend: %Friend{guid: guid}}) do
    <<result, guid::little-size(64)>>
  end
end
