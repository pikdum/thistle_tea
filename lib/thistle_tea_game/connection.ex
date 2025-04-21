defmodule ThistleTeaGame.Connection do
  alias ThistleTeaGame.Opcodes
  alias ThistleTeaGame.Effect
  alias ThistleTeaGame.Packet
  alias ThistleTeaGame.ClientPacket
  alias ThistleTeaGame.Connection.Crypto

  require Logger

  @cmsg_auth_session Opcodes.get(:CMSG_AUTH_SESSION)

  defstruct [
    :session_key,
    packet_stream: <<>>,
    raw_packet_queue: [],
    decoded_packet_queue: [],
    effect_queue: [],
    send_i: 0,
    send_j: 0,
    recv_i: 0,
    recv_j: 0,
    seed: :crypto.strong_rand_bytes(4)
  ]

  def receive_data(%__MODULE__{} = conn, data) do
    Map.put(conn, :packet_stream, conn.packet_stream <> data)
  end

  def add_effect(%__MODULE__{} = conn, effect) when is_list(effect) do
    Map.put(conn, :effect_queue, conn.effect_queue ++ effect)
  end

  def add_effect(%__MODULE__{} = conn, effect) do
    Map.put(conn, :effect_queue, conn.effect_queue ++ [effect])
  end

  # full header is 6 bytes, so any less is incomplete
  def enqueue_packets(%__MODULE__{packet_stream: packet_stream} = conn)
      when byte_size(packet_stream) < 6 do
    conn
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

    Map.merge(conn, %{
      packet_stream: rest,
      raw_packet_queue: conn.raw_packet_queue ++ [packet]
    })
    |> enqueue_packets()
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

        Map.merge(conn, %{
          packet_stream: rest,
          raw_packet_queue: conn.raw_packet_queue ++ [packet]
        })
        |> enqueue_packets()

      {:error, conn, _} ->
        conn
    end
  end

  def decode_packets(%__MODULE__{raw_packet_queue: []} = conn) do
    conn
  end

  def decode_packets(
        %__MODULE__{
          raw_packet_queue: [raw_packet | rest],
          decoded_packet_queue: decoded_packet_queue
        } = conn
      ) do
    case ClientPacket.decode(raw_packet) do
      {:ok, decoded} ->
        Map.merge(conn, %{
          raw_packet_queue: rest,
          decoded_packet_queue: decoded_packet_queue ++ [decoded]
        })
        |> decode_packets()

      {:error, :unhandled_opcode, opcode} ->
        Logger.warning("Unhandled: #{Opcodes.get(opcode)}")

        Map.merge(conn, %{
          raw_packet_queue: rest,
          decoded_packet_queue: decoded_packet_queue
        })
        |> decode_packets()
    end
  end

  def handle_packets(%__MODULE__{decoded_packet_queue: []} = conn) do
    conn
  end

  def handle_packets(%__MODULE__{decoded_packet_queue: [decoded_packet | rest]} = conn) do
    opcode = decoded_packet |> Packet.opcode() |> Opcodes.get()

    case Packet.handle(decoded_packet, conn) do
      {:ok, conn} ->
        Logger.debug("Handled: #{opcode}")

        Map.merge(conn, %{
          decoded_packet_queue: rest
        })
        |> handle_packets()

      {:error, _} ->
        Map.merge(conn, %{
          decoded_packet_queue: rest
        })
        |> handle_packets()

      _ ->
        conn
    end
  end

  def process_effects(%__MODULE__{effect_queue: []} = conn, _socket) do
    conn
  end

  # TODO: since effects can trigger effects, i think they'd get lost with how this works now
  def process_effects(%__MODULE__{effect_queue: [effect | rest]} = conn, socket) do
    case Effect.process(effect, conn, socket) do
      {:ok, conn} ->
        conn
        |> Map.put(:effect_queue, rest)
        |> process_effects(socket)

      _ ->
        conn
        |> Map.put(:effect_queue, rest)
        |> process_effects(socket)
    end
  end
end
