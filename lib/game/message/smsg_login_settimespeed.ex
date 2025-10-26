defmodule ThistleTea.Game.Message.SmsgLoginSettimespeed do
  use ThistleTea.Game.ServerMessage, :SMSG_LOGIN_SETTIMESPEED

  defstruct [
    :datetime,
    :timescale
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{datetime: datetime, timescale: timescale}) do
    <<datetime::little-size(32), timescale::little-float-size(32)>>
  end
end
