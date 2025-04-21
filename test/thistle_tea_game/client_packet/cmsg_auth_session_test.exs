defmodule ThistleTeaGame.ClientPacket.CmsgAuthSessionTest do
  use ExUnit.Case

  alias ThistleTeaGame.Effect
  alias ThistleTeaGame.Connection
  alias ThistleTeaGame.ServerPacket.SmsgAuthResponse
  alias ThistleTea.Test.Support.Util
  alias ThistleTeaGame.ClientPacket.CmsgAuthSession

  @username "PIKDUM"
  @seed <<8, 52, 218, 78>>
  @session_key <<191, 96, 16, 0, 167, 242, 236, 112, 154, 39, 62, 150, 8, 135, 8, 26, 2, 102, 232,
                 212, 185, 42, 238, 17, 159, 220, 202, 245, 180, 241, 121, 12, 29, 217, 244, 22,
                 47, 170, 64, 148>>
  @client_seed <<111, 73, 240, 138>>
  @client_proof <<195, 69, 164, 98, 116, 81, 66, 183, 137, 253, 243, 14, 202, 37, 21, 225, 41,
                  125, 4, 75>>

  describe "verify_proof/2" do
    test "returns error if proof is invalid" do
      conn = %Connection{
        seed: :crypto.strong_rand_bytes(4),
        session_key: :crypto.strong_rand_bytes(40)
      }

      packet = %CmsgAuthSession{
        username: Util.random_string(10),
        client_seed: :crypto.strong_rand_bytes(4),
        client_proof: :crypto.strong_rand_bytes(20)
      }

      {:error, _} = CmsgAuthSession.verify_proof(conn, packet)
    end

    test "returns success + adds session_key if proof is valid" do
      conn = %Connection{
        seed: @seed,
        session_key: @session_key
      }

      packet = %CmsgAuthSession{
        username: @username,
        client_seed: @client_seed,
        client_proof: @client_proof
      }

      {:ok, conn} = CmsgAuthSession.verify_proof(conn, packet)

      assert conn.session_key == @session_key
    end
  end

  describe "handle/2" do
    test "adds effect on success" do
      :ets.insert(:session, {@username, @session_key})

      packet = %CmsgAuthSession{
        username: @username,
        client_seed: @client_seed,
        client_proof: @client_proof
      }

      conn = %Connection{
        seed: @seed,
        session_key: @session_key
      }

      {:ok, conn} = CmsgAuthSession.handle(packet, conn)
      [effect | _] = conn.effect_queue

      assert %Effect.SendPacket{
               packet: %SmsgAuthResponse{
                 result: 0x0C,
                 billing_time: 0,
                 billing_flags: 0,
                 billing_rested: 0,
                 queue_position: 0
               }
             } == effect
    end
  end
end
