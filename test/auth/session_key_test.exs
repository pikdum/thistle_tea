defmodule ThistleTea.Auth.SessionKeyTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Auth.SessionKey

  setup [:session]

  describe "verify_world_proof/4" do
    test "accepts the client's proof over the stored session key", ctx do
      proof = SessionKey.world_proof(ctx.username, ctx.client_seed, ctx.server_seed, ctx.key)

      assert SessionKey.verify_world_proof(ctx.username, ctx.client_seed, ctx.server_seed, proof) == {:ok, ctx.key}
    end

    test "rejects a mismatched proof or an unknown username", ctx do
      proof = SessionKey.world_proof(ctx.username, ctx.client_seed, ctx.server_seed, ctx.key)

      assert SessionKey.verify_world_proof(ctx.username, ctx.client_seed, <<0::32>>, proof) == :error
      assert SessionKey.verify_world_proof("#{ctx.username}_OTHER", ctx.client_seed, ctx.server_seed, proof) == :error
    end
  end

  defp session(_context) do
    username = "SESSION_KEY_TEST_#{System.unique_integer([:positive])}"
    key = :crypto.strong_rand_bytes(40)
    :ok = SessionKey.put(username, key)
    on_exit(fn -> :ets.delete(:session, username) end)

    %{username: username, key: key, client_seed: <<1, 2, 3, 4>>, server_seed: <<5, 6, 7, 8>>}
  end
end
