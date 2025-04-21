defmodule ThistleTeaGame.ClientPacket do
  alias ThistleTeaGame.ClientPacket.Parse
  alias ThistleTeaGame.ClientPacket.CmsgAuthSession

  defstruct [
    :opcode,
    :size,
    :payload
  ]

  @cmsg_auth_session 0x1ED

  # TODO: can i delegate this to CmsgAuthSession?
  def decode(%__MODULE__{opcode: @cmsg_auth_session, payload: payload}) do
    with <<build::little-size(32), server_id::little-size(32), rest::binary>> <- payload,
         {:ok, username, rest} <- Parse.parse_string(rest),
         <<client_seed::little-bytes-size(4), client_proof::little-bytes-size(20), _rest::binary>> <-
           rest do
      {:ok,
       %CmsgAuthSession{
         build: build,
         server_id: server_id,
         username: username,
         client_seed: client_seed,
         client_proof: client_proof
       }}
    else
      _ -> {:error, :invalid_packet}
    end
  end

  def decode(%__MODULE__{opcode: opcode}) do
    {:error, :unknown_opcode, opcode}
  end
end
