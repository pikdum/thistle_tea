defmodule ThistleTea.Game.Inbound.CmsgNameQuery do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_NAME_QUERY, while_possessed: true

  alias ThistleTea.Game.Inbound.Query
  alias ThistleTea.Game.World.Entity.Player.Queries

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: guid |> Queries.name() |> Query.reply(state)
end
