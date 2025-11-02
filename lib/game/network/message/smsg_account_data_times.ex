defmodule ThistleTea.Game.Network.Message.SmsgAccountDataTimes do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ACCOUNT_DATA_TIMES

  defstruct data: [0, 0, 0, 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{data: data}) do
    Enum.reduce(data, <<>>, fn value, acc ->
      acc <> <<value::little-size(32)>>
    end)
  end
end
