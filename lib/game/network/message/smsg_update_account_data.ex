defmodule ThistleTea.Game.Network.Message.SmsgUpdateAccountData do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_UPDATE_ACCOUNT_DATA

  defstruct [:type, data: ""]

  @impl ServerMessage
  def to_binary(%__MODULE__{type: type, data: ""}), do: <<type::little-size(32), 0::little-size(32)>>

  def to_binary(%__MODULE__{type: type, data: data}),
    do: <<type::little-size(32), byte_size(data)::little-size(32)>> <> :zlib.compress(data)
end
