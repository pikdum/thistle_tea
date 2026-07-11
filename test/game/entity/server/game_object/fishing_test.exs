defmodule ThistleTea.Game.Entity.Server.GameObject.FishingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Fishing, as: FishingState
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Server.GameObject.Fishing

  describe "use/3" do
    test "only the owner can use a bobber" do
      state = bobber(%FishingState{owner_guid: 42, ready?: true})
      assert {{:error, :not_owner}, ^state} = Fishing.use(state, 43, 300)
    end

    test "an early click consumes the bobber" do
      state = bobber(%FishingState{owner_guid: 42, ready?: false})
      assert {{:error, :not_hooked}, state} = Fishing.use(state, 42, 300)
      assert state.internal.fishing.consumed?
    end
  end

  describe "catch_success?/3" do
    test "uses the VMangos linear area difficulty check" do
      refute Fishing.catch_success?(129, 130, 1)
      assert Fishing.catch_success?(130, 130, 5)
      refute Fishing.catch_success?(130, 130, 6)
      assert Fishing.catch_success?(225, 130, 100)
    end
  end

  defp bobber(fishing) do
    %GameObject{object: %{guid: 1}, internal: %Internal{fishing: fishing}}
  end
end
