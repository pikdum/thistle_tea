defmodule ThistleTea.Game.World.Loader.GossipTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.Gossip

  describe "trainer_of?/4" do
    test "allows another race to use a mount trainer at exalted" do
      entry = System.unique_integer([:positive, :monotonic])
      key = {:trainer, entry}
      :ets.insert(Gossip, {key, %{type: 1, class: 0, race: 1}})
      on_exit(fn -> :ets.delete(Gossip, key) end)

      assert Gossip.trainer_of?(entry, 1, 1)
      refute Gossip.trainer_of?(entry, 1, 3)
      assert Gossip.trainer_of?(entry, 1, 3, true)
    end
  end
end
