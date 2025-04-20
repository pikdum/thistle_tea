defmodule ThistleTeaGame.ConnectionTest do
  use ExUnit.Case

  alias ThistleTea.Test.DecryptHeaderRecording
  alias ThistleTeaGame.Connection

  describe "enqueue_packets/1" do
    test "can queue all packets in recording" do
      for %{input: input, output: output} <- DecryptHeaderRecording.log() do
        conn =
          %Connection{
            session_key: DecryptHeaderRecording.session_key()
          }
          |> Map.merge(input)
          |> Connection.enqueue_packets()

        assert not Enum.empty?(conn.packet_queue)

        [first | _] = conn.packet_queue

        assert output[:header] == <<first.size::big-size(16), first.opcode::little-size(32)>>
      end
    end
  end
end
