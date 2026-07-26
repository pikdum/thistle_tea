defmodule ThistleTea.Game.World.Visibility.TapTest do
  use ExUnit.Case, async: false

  import Bitwise

  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility.Tap

  @dynamic_flag_tapped 0x0004

  describe "personalize/2" do
    test "clears the gray tag for the player who tapped a living mob" do
      viewer_guid = Guid.from_low_guid(:player, unique_guid())
      mob_guid = Guid.from_low_guid(:mob, 1, unique_guid())

      Metadata.put(mob_guid, %{
        tapped_player: viewer_guid,
        tapped_group_id: nil,
        loot_projection: nil
      })

      on_exit(fn -> Metadata.delete(mob_guid) end)

      update = %UpdateObject{
        object: %Object{guid: mob_guid},
        unit: %Unit{dynamic_flags: @dynamic_flag_tapped}
      }

      personalized = Tap.personalize(update, viewer_guid)

      assert (personalized.unit.dynamic_flags &&& @dynamic_flag_tapped) == 0
    end

    test "keeps the gray tag for another player" do
      tapper_guid = Guid.from_low_guid(:player, unique_guid())
      viewer_guid = Guid.from_low_guid(:player, unique_guid())
      mob_guid = Guid.from_low_guid(:mob, 1, unique_guid())

      Metadata.put(mob_guid, %{
        tapped_player: tapper_guid,
        tapped_group_id: nil,
        loot_projection: nil
      })

      on_exit(fn -> Metadata.delete(mob_guid) end)

      update = %UpdateObject{
        object: %Object{guid: mob_guid},
        unit: %Unit{dynamic_flags: @dynamic_flag_tapped}
      }

      personalized = Tap.personalize(update, viewer_guid)

      assert (personalized.unit.dynamic_flags &&& @dynamic_flag_tapped) != 0
    end
  end

  defp unique_guid do
    System.unique_integer([:positive, :monotonic])
  end
end
