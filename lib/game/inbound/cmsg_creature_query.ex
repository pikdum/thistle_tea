defmodule ThistleTea.Game.Inbound.CmsgCreatureQuery do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_CREATURE_QUERY, while_possessed: true

  alias ThistleTea.Game.Inbound.Query
  alias ThistleTea.Game.World.Entity.Player.Queries

  defstruct [:entry, :guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<entry::little-size(32), guid::little-size(64)>> = payload

    %__MODULE__{
      entry: entry,
      guid: guid
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{entry: entry, guid: guid}, state), do: entry |> Queries.creature(guid) |> Query.reply(state)
end
