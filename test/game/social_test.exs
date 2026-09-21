defmodule ThistleTea.Game.SocialTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Social

  setup [:social]

  describe "add/3" do
    test "keeps friend and ignore membership independent", %{social: social} do
      {:ok, social} = Social.add(social, :friend, 11)
      {:ok, social} = Social.add(social, :ignore, 11)
      assert Social.member?(social, :friend, 11)
      assert Social.member?(social, :ignore, 11)
      assert Social.add(social, :friend, 11) == {:error, :already}
      assert Social.add(social, :ignore, 11) == {:error, :already}
    end

    test "rejects self and invalid targets", %{social: social} do
      for kind <- [:friend, :ignore] do
        assert Social.add(social, kind, 10) == {:error, :self}
        assert Social.add(social, kind, 0) == {:error, :not_found}
        assert Social.add(social, kind, nil) == {:error, :not_found}
      end
    end

    test "enforces independent vanilla limits without replacing entries", %{social: social} do
      social =
        Enum.reduce([:friend, :ignore], social, fn kind, social ->
          Enum.reduce(101..(100 + Social.limit(kind)), social, fn guid, social ->
            {:ok, social} = Social.add(social, kind, guid)
            social
          end)
        end)

      assert MapSet.size(social.friends) == 50
      assert MapSet.size(social.ignored) == 25

      for kind <- [:friend, :ignore] do
        assert Social.add(social, kind, 200) == {:error, :full}
        assert Social.add(social, kind, 101) == {:error, :already}
        {:ok, changed} = social |> Social.remove(kind, 101) |> Social.add(kind, 200)
        assert Social.member?(changed, kind, 200)
        refute Social.member?(changed, kind, 101)
      end
    end
  end

  describe "remove/3" do
    test "removes only the requested relationship and is idempotent", %{social: social} do
      {:ok, social} = Social.add(social, :friend, 11)
      {:ok, social} = Social.add(social, :ignore, 11)
      removed = Social.remove(social, :friend, 11)
      refute Social.member?(removed, :friend, 11)
      assert Social.member?(removed, :ignore, 11)
      assert Social.remove(removed, :friend, 11) == removed
    end
  end

  defp social(_context), do: %{social: %Social{owner_guid: 10}}
end
