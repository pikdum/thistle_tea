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
        %__MODULE__{} = packet,
        %Connection{} = conn
      ) do
    case verify_proof(conn, packet) do
      {:ok, conn} ->
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

      {:error, _} ->
        {:error, conn}
    end
  end

  def verify_proof(%Connection{seed: seed, session_key: session_key} = conn, %__MODULE__{
        username: username,
        client_seed: client_seed,
        client_proof: client_proof
      }) do
    server_proof =
      :crypto.hash(
        :sha,
        username <> <<0::little-size(32)>> <> client_seed <> seed <> session_key
      )

    if client_proof == server_proof do
      {:ok, conn}
    else
      {:error, :proof_mismatch}
    end
  end
end
