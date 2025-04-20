defmodule ThistleTeaGame.ClientPacket.CmsgAuthSession do
  defstruct [
    :build,
    :server_id,
    :username,
    :client_seed,
    :client_proof
  ]

  defimpl ThistleTeaGame.Packet do
    def handle(
          %ThistleTeaGame.ClientPacket.CmsgAuthSession{
            username: username,
            client_seed: client_seed,
            client_proof: client_proof
          } = packet,
          conn
        ) do
      # [{^username, session_key}] = :ets.lookup(:session, username)
      :ok
    end
  end
end
