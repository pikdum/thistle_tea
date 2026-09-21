defmodule ThistleTea.Game.Player.VendorVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Player.Vendor
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @moduletag :vmangos_db

  describe "valid_vendor?/2" do
    test "accepts Corina Steele's vanilla vendor and repair flags from seed data" do
      template = Mangos.Repo.get_by!(Mangos.CreatureTemplate, entry: 54)
      guid = Guid.from_low_guid(:mob, 54, System.unique_integer([:positive, :monotonic]))
      Metadata.put(guid, %{alive?: true, npc_flags: template.npc_flags})
      SpatialHash.update(:mobs, guid, WorldRef.open(0), 2.0, 0.0, 0.0)

      on_exit(fn ->
        Metadata.delete(guid)
        SpatialHash.remove(:mobs, guid)
      end)

      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 100},
        player: %Player{},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      assert template.npc_flags == 0x4004
      assert Vendor.valid_vendor?(character, guid)
    end
  end
end
