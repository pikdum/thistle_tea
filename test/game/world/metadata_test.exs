defmodule ThistleTea.Game.World.MetadataTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Metadata

  setup do
    table = Metadata.init(:"metadata_test_#{System.unique_integer([:positive])}")

    on_exit(fn ->
      if is_atom(table) and :ets.whereis(table) != :undefined do
        :ets.delete(table)
      end
    end)

    %{table: table}
  end

  describe "init/1" do
    test "creates a named table" do
      table = :"metadata_init_test_#{System.unique_integer([:positive])}"
      assert Metadata.init(table) == table
      assert :ets.whereis(table) != :undefined
      :ets.delete(table)
    end
  end

  describe "put/3 and get/2" do
    test "stores and fetches metadata", %{table: table} do
      guid = 123
      assert :ok == Metadata.put(table, guid, %{name: "foo"})
      assert Metadata.get(table, guid) == %{name: "foo"}
    end
  end

  describe "update/3" do
    test "merges metadata values", %{table: table} do
      guid = 456
      Metadata.put(table, guid, %{name: "foo"})
      Metadata.update(table, guid, realm: "bar")
      assert Metadata.get(table, guid) == %{name: "foo", realm: "bar"}
    end

    test "creates metadata when missing", %{table: table} do
      guid = 789
      Metadata.update(table, guid, %{name: "baz"})
      assert Metadata.get(table, guid) == %{name: "baz"}
    end
  end

  describe "query/3" do
    test "returns selected keys", %{table: table} do
      guid = 111
      Metadata.put(table, guid, %{name: "foo", realm: "bar"})
      assert Metadata.query(table, guid, [:name]) == %{name: "foo"}
    end

    test "returns nil when missing", %{table: table} do
      assert Metadata.query(table, 222, [:name]) == nil
    end
  end

  describe "delete/2" do
    test "removes metadata", %{table: table} do
      guid = 333
      Metadata.put(table, guid, %{name: "foo"})
      Metadata.delete(table, guid)
      assert Metadata.get(table, guid) == nil
    end
  end

  describe "find_guid_by/3" do
    test "finds guid by metadata value", %{table: table} do
      guid = 444
      Metadata.put(table, guid, %{name: "target"})
      assert Metadata.find_guid_by(table, :name, "target") == guid
      assert Metadata.find_guid_by(table, :name, "missing") == nil
    end
  end
end
