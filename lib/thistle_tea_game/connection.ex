defmodule ThistleTeaGame.Connection do
  alias ThistleTeaGame.Effect
  alias ThistleTeaGame.Packet
  alias ThistleTeaGame.ClientPacket
  alias ThistleTeaGame.Connection.Crypto

  require Logger

  @cmsg_auth_session ThistleTeaGame.Opcodes.get(:CMSG_AUTH_SESSION)

  defstruct [
    :session_key,
    packet_stream: <<>>,
    packet_queue: [],
    effect_queue: [],
    send_i: 0,
    send_j: 0,
    recv_i: 0,
    recv_j: 0,
    seed: :crypto.strong_rand_bytes(4)
  ]

  def receive_data(%__MODULE__{} = conn, data) do
    Map.put(conn, :packet_stream, Map.get(conn, :packet_stream, <<>>) <> data)
  end

  def add_effect(%__MODULE__{} = conn, effect) when is_list(effect) do
    Map.put(conn, :effect_queue, conn.effect_queue ++ effect)
  end

  def add_effect(%__MODULE__{} = conn, effect) do
    Map.put(conn, :effect_queue, conn.effect_queue ++ [effect])
  end

  # handle separately since this isn't encrypted
  def enqueue_packets(
        %__MODULE__{
          packet_stream:
            <<size::big-size(16), @cmsg_auth_session::little-size(32),
              payload::binary-size(size - 4), rest::binary>>
        } = conn
      ) do
    packet = %ClientPacket{
      opcode: @cmsg_auth_session,
      size: size,
      payload: payload
    }

    conn =
      Map.merge(conn, %{
        packet_stream: rest,
        packet_queue: conn.packet_queue ++ [packet]
      })

    enqueue_packets(conn)
  end

  def enqueue_packets(%__MODULE__{} = conn) do
    case Crypto.decrypt_header(conn) do
      {:ok, conn, decrypted_header} ->
        <<size::big-size(16), opcode::little-size(32)>> = decrypted_header

        <<_encrypted_header::bytes-size(6), payload::binary-size(size - 4), rest::binary>> =
          conn.packet_stream

        packet = %ClientPacket{
          opcode: opcode,
          size: size,
          payload: payload
        }

        conn =
          Map.merge(conn, %{
            packet_stream: rest,
            packet_queue: conn.packet_queue ++ [packet]
          })

        enqueue_packets(conn)

      {:error, conn, _} ->
        conn
    end
  end

  def handle_packets(%__MODULE__{} = conn) do
    Enum.reduce(conn.packet_queue, conn, fn packet, conn ->
      case ClientPacket.decode(packet) do
        {:ok, decoded} ->
          Packet.handle(decoded, conn)

        {:error, reason} ->
          Logger.error("Failed to decode packet: #{inspect(reason)}")
          conn
      end
    end)
    |> Map.put(:packet_queue, [])
  end

  def process_effects(%__MODULE__{} = conn, socket) do
    Enum.reduce(conn.effect_queue, conn, fn effect, conn ->
      Effect.process(effect, conn, socket)
    end)
    |> Map.put(:effect_queue, [])
  end
end
