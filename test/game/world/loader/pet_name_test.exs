defmodule ThistleTea.Game.World.Loader.PetNameTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.PetName, as: PetNameLoader

  setup do
    %{table: :ets.new(__MODULE__, [:set, :public])}
  end

  describe "generate/3" do
    test "joins one drawn opening with one drawn closing", %{table: table} do
      :ok = PetNameLoader.put(416, ["Aba", "Biz"], ["gak", "zig", "tik"], table)

      assert PetNameLoader.generate(416, fn _count -> 1 end, table) == "Abagak"
      assert PetNameLoader.generate(416, & &1, table) == "Biztik"
    end

    test "leaves entries without both halves to their template name", %{table: table} do
      :ok = PetNameLoader.put(417, ["Aba"], [], table)

      assert PetNameLoader.generate(417, & &1, table) == nil
      assert PetNameLoader.generate(1860, & &1, table) == nil
    end
  end
end
