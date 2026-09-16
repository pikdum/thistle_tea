defmodule ThistleTea.Game.Network.UpdateBatcherTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Network.UpdateBatcher
  alias ThistleTea.Game.Network.UpdateObject

  describe "batch/3" do
    test "serializes queued removals with ordinary updates" do
      update = values_update(1)
      removal = UpdateObject.out_of_range([0x1FC0000000028427, 0xF12002AFE800496A], has_transport: true)
      GenServer.cast(self(), {:send_packet, removal})

      {packet, updates} = UpdateBatcher.batch(update, 99)
      <<1::little-size(32), 0, values_body::binary>> = UpdateObject.to_packet(update, 99).payload
      <<1::little-size(32), 1, removal_body::binary>> = UpdateObject.to_packet(removal, 99).payload

      assert updates == [update, removal]
      assert packet.payload == <<2::little-size(32), 1>> <> values_body <> removal_body
    end

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

  describe "batch/4" do
    test "filters hidden initial and queued objects before serialization" do
      GenServer.cast(self(), {:send_packet, values_update(2)})
      GenServer.cast(self(), {:send_packet, values_update(3)})

      {_packet, updates} = UpdateBatcher.batch(values_update(1), 99, & &1, &(&1.object.guid == 2))
      assert [%UpdateObject{object: %Object{guid: 2}}] = updates
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
