defmodule ThistleTea.Game.Network.Message.SmsgGuildInfo do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GUILD_INFO

  defstruct [:name, :created_date, :members, :accounts]

  @impl ServerMessage
  def to_binary(%__MODULE__{name: name, created_date: %Date{} = date, members: members, accounts: accounts}) do
    name <>
      <<0, date.day::little-size(32), date.month::little-size(32), date.year::little-size(32), members::little-size(32),
        accounts::little-size(32)>>
  end
end
