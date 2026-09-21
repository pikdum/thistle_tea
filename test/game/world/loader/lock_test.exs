defmodule ThistleTea.Game.World.Loader.LockTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Lock, as: LockData
  alias ThistleTea.Game.Entity.Data.Lock.Requirement
  alias ThistleTea.Game.World.Loader.Lock, as: LockLoader

  describe "load/2" do
    test "retains requirement ordering and ignores unused slots" do
      table = :ets.new(__MODULE__, [:set])
      LockLoader.load([%Lock{id: 36, ty_0: 1, property_0: 3467, ty_1: 2, property_1: 1, required_skill_1: 100}], table)

      assert LockLoader.get(36, table) == %LockData{
               id: 36,
               requirements: [%Requirement{type: :item, index: 3467}, %Requirement{type: :skill, index: 1, skill: 100}]
             }

      assert LockLoader.get(999, table) == nil
    end
  end
end
