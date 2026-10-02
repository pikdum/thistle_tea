defmodule ThistleTea.Game.World.Entity.Player.VendorVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.Player.Vendor
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Test.Unique

  @moduletag :vmangos_db

  describe "valid_vendor?/2" do
    test "accepts Corina Steele's vanilla vendor and repair flags from seed data" do
      template = Mangos.Repo.get_by!(Mangos.CreatureTemplate, entry: 54)
      guid = Guid.from_low_guid(:mob, 54, Unique.integer())
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
