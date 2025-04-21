defmodule ThistleTeaGame.ClientPacket.CmsgAuthSession do
  alias ThistleTeaGame.Connection
  alias ThistleTeaGame.Effect
  alias ThistleTeaGame.ServerPacket

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
    def encode(packet), do: nil
  end

  # TODO: can handle be a behavior?
  def handle(
        %__MODULE__{
          username: username,
          client_seed: client_seed,
          client_proof: client_proof
        },
        %Connection{} = conn
      ) do
    with [{^username, session_key}] <- :ets.lookup(:session, username),
         {:ok, conn} <- verify_proof(conn, session_key, username, client_seed, client_proof) do
      effect = %Effect.SendPacket{
        packet: %ServerPacket.SmsgAuthResponse{
          result: 0x0C,
          billing_time: 0,
          billing_flags: 0,
          billing_rested: 0,
          queue_position: 0
        }
      }

      {:ok, conn |> Connection.add_effect(effect)}
    else
      _ ->
        {:error, conn}
    end
  end

  def verify_proof(%Connection{} = conn, session_key, username, client_seed, client_proof) do
    server_proof =
      :crypto.hash(
        :sha,
        username <> <<0::little-size(32)>> <> client_seed <> conn.seed <> session_key
      )

    if client_proof == server_proof do
      {:ok, conn |> Map.put(:session_key, session_key)}
    else
      {:error, :proof_mismatch}
    end
  end
end
