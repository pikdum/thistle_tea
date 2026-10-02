defmodule ThistleTea.Game.Network.Message.SmsgAccountDataMd5 do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ACCOUNT_DATA_MD5

  defstruct digests: List.duplicate(<<0::128>>, 8)

  @impl ServerMessage
  def to_binary(%__MODULE__{digests: digests}), do: IO.iodata_to_binary(digests)
end
