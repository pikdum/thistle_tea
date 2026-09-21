defmodule ThistleTea.Game.World.Loader.LockDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Lock.Requirement
  alias ThistleTea.Game.World.Loader.Lock, as: LockLoader

  @moduletag :dbc_db

  describe "load_all/1" do
    test "loads gathering, treasure and key requirements" do
      table = :ets.new(__MODULE__, [:set])
      LockLoader.load_all(table)
      assert LockLoader.get(29, table).requirements == [%Requirement{type: :skill, index: 2, skill: 0}]
      assert LockLoader.get(39, table).requirements == [%Requirement{type: :skill, index: 3, skill: 65}]
      assert %Requirement{type: :skill, index: 5} in LockLoader.get(2, table).requirements
      assert %Requirement{type: :item, index: 3467} in LockLoader.get(36, table).requirements
      assert LockLoader.get(85, table).requirements == []
    end
  end
end
