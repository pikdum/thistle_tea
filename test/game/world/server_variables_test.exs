defmodule ThistleTea.Game.World.ServerVariablesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.ServerVariables

  setup do
    ServerVariables.init(__MODULE__)
    :ok
  end

  describe "put/3" do
    test "retains unsigned values and returns immutable snapshots" do
      assert ServerVariables.get(0, __MODULE__) == 0
      assert ServerVariables.put(0, 0xFFFFFFFF, __MODULE__) == :ok
      snapshot = ServerVariables.snapshot(__MODULE__)
      assert snapshot == %{0 => 0xFFFFFFFF}
      assert ServerVariables.put(0, 6, __MODULE__) == :ok
      assert ServerVariables.get(0, __MODULE__) == 6
      assert snapshot[0] == 0xFFFFFFFF
    end

    test "rejects values outside the packet-independent unsigned domain" do
      for {index, value} <- [{-1, 0}, {0, -1}, {0x100000000, 0}, {0, 0x100000000}, {1, nil}, {1, 2.0}] do
        assert ServerVariables.put(index, value, __MODULE__) == {:error, :invalid_variable}
      end

      assert ServerVariables.snapshot(__MODULE__) == %{}
    end
  end

  describe "init/1" do
    test "preserves an existing table and resets with its application lifetime" do
      ServerVariables.put(30_050, 6, __MODULE__)
      ServerVariables.init(__MODULE__)
      assert ServerVariables.get(30_050, __MODULE__) == 6
      :ets.delete(__MODULE__)
      ServerVariables.init(__MODULE__)
      assert ServerVariables.get(30_050, __MODULE__) == 0
    end
  end
end
