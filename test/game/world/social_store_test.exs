defmodule ThistleTea.Game.World.SocialStoreTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Social
  alias ThistleTea.Game.World.SocialStore

  setup [:store]

  describe "put/2" do
    test "retains independent lists and derives reverse friend relationships", %{table: table} do
      assert SocialStore.get(10, table) == %Social{owner_guid: 10}
      {:ok, social} = Social.add(SocialStore.get(10, table), :friend, 11)
      {:ok, social} = Social.add(social, :ignore, 11)
      assert SocialStore.put(social, table) == social
      assert SocialStore.ignores?(10, 11, table)
      refute SocialStore.ignores?(11, 10, table)
      assert SocialStore.followers(11, table) == [10]

      social |> Social.remove(:friend, 11) |> SocialStore.put(table)
      assert SocialStore.followers(11, table) == []
      assert SocialStore.ignores?(10, 11, table)
    end
  end

  defp store(_context), do: %{table: SocialStore.init(__MODULE__)}
end
