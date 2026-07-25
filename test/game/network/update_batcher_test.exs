defmodule ThistleTea.Game.Network.UpdateBatcherTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Network.UpdateBatcher
  alias ThistleTea.Game.Network.UpdateObject

  describe "batch/3" do
    test "personalizes updates drained out of the mailbox too" do
      GenServer.cast(self(), {:send_packet, values_update(2)})
      GenServer.cast(self(), {:send_packet, values_update(3)})

      {_packet, updates} = UpdateBatcher.batch(values_update(1), 99, &clear_dynamic_flags/1)

      assert Enum.map(updates, & &1.object.guid) == [1, 2, 3]
      assert Enum.all?(updates, &(&1.unit.dynamic_flags == 0))
    end

    test "keeps only the newest values block per guid" do
      GenServer.cast(self(), {:send_packet, values_update(1, dynamic_flags: 7)})

      {_packet, updates} = UpdateBatcher.batch(values_update(1), 99)

      assert [%UpdateObject{unit: %Unit{dynamic_flags: 7}}] = updates
    end
  end

  defp values_update(guid, opts \\ []) do
    %UpdateObject{
      update_type: :values,
      object_type: :unit,
      object: %Object{guid: guid},
      unit: %Unit{dynamic_flags: Keyword.get(opts, :dynamic_flags, 5)}
    }
  end

  defp clear_dynamic_flags(%UpdateObject{unit: %Unit{} = unit} = update) do
    %{update | unit: %{unit | dynamic_flags: 0}}
  end
end
