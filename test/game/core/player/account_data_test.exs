defmodule ThistleTea.Game.Core.Player.AccountDataTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Player.AccountData

  describe "owner/3" do
    test "files shared caches under the account and the rest under the character" do
      assert AccountData.owner(0, 7, 42) == {:account, 7}
      assert AccountData.owner(4, 7, 42) == {:account, 7}
      assert AccountData.owner(1, 7, 42) == {:character, 42}
      assert AccountData.owner(7, 7, 42) == {:character, 42}
      assert AccountData.owner(3, 7, nil) == nil
    end
  end

  describe "digest/1" do
    test "hashes empty caches to zeros" do
      assert AccountData.digest("") == <<0::128>>
      assert AccountData.digest("SET x 1") == :crypto.hash(:md5, "SET x 1")
    end
  end

  describe "type?/1" do
    test "accepts the eight 1.12 caches" do
      assert Enum.all?(0..7, &AccountData.type?/1)
      refute AccountData.type?(8)
    end
  end
end
