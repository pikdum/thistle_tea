defmodule ThistleTea.Game.World.Loader.PetNameVmangosTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.PetName, as: PetNameLoader

  @moduletag :vmangos_db

  describe "load_all/1" do
    test "caches both halves for every warlock demon" do
      table = :ets.new(__MODULE__, [:set, :public])
      PetNameLoader.load_all(table)

      for entry <- [416, 417, 1860, 1863] do
        assert [{^entry, openings, closings}] = :ets.lookup(table, entry)
        assert tuple_size(openings) > 20 and tuple_size(closings) > 20
      end

      assert PetNameLoader.generate(416, fn _count -> 1 end, table) =~ ~r/\A[A-Z][a-z]+\z/
    end
  end
end
