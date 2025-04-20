defmodule ThistleTeaGame.ClientPacket.CmsgAuthSession do
  alias ThistleTeaGame.Connection

  defstruct [
    :build,
    :server_id,
    :username,
    :client_seed,
    :client_proof
  ]

  # TODO: can i wire this up with a macro?
  defimpl ThistleTeaGame.Packet do
    def handle(packet, conn), do: ThistleTeaGame.ClientPacket.CmsgAuthSession.handle(packet, conn)
  end

  # TODO: can handle be a behavior?
  def handle(
        %__MODULE__{
          username: username,
          client_seed: client_seed,
          client_proof: client_proof
        } = packet,
        %Connection{} = conn
      ) do
    with [{^username, session_key}] <- :ets.lookup(:session, username),
         {:ok, conn} <- verify_proof(conn, username, client_seed, client_proof) do
      # TODO: how to model sending packet side effects?
      {:ok, conn}
    else
      _ ->
        {:error, conn}
    end
  end

  defp verify_proof(%Connection{} = conn, username, client_seed, client_proof) do
    server_proof =
      :crypto.hash(
        :sha,
        username <> <<0::little-size(32)>> <> client_seed <> conn.seed <> conn.session_key
      )

    if client_proof == server_proof do
      {:ok, conn}
    else
      {:error, nil}
    end
  end
end
