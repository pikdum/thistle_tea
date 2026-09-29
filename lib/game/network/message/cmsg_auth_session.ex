defmodule ThistleTea.Game.Network.Message.CmsgAuthSession do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUTH_SESSION

  defstruct [
    :build,
    :server_id,
    :username,
    :client_seed,
    :client_proof
  ]

  @impl ClientMessage
  def from_binary(payload) do
    with <<build::little-size(32), server_id::little-size(32), rest::binary>> <- payload,
         {:ok, username, rest} <- BinaryUtils.parse_string(rest),
         <<client_seed::little-bytes-size(4), client_proof::little-bytes-size(20), _rest::binary>> <-
           rest do
      %__MODULE__{
        build: build,
        server_id: server_id,
        username: username,
        client_seed: client_seed,
        client_proof: client_proof
      }
    end
  end
end
