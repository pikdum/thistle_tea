defmodule ThistleTea.Game.World.Loader.SummonOwnerTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.Summon

  @unit_flag_player_controlled 0x00000008

  describe "attach_owner/2" do
    test "stamps owner guids and the player-controlled flag for player owners" do
      owner_guid = Guid.from_low_guid(:player, 7)
      summon = Summon.attach_owner(mob(flags: 0x1000), owner_guid)

      assert summon.unit.summoned_by == owner_guid
      assert summon.unit.created_by == owner_guid
      assert (summon.unit.flags &&& @unit_flag_player_controlled) != 0
      assert (summon.unit.flags &&& 0x1000) != 0
    end

    test "handles nil unit flags" do
      summon = Summon.attach_owner(mob(flags: nil), Guid.from_low_guid(:player, 7))

      assert summon.unit.flags == @unit_flag_player_controlled
    end

    test "does not add the player-controlled flag for creature owners" do
      owner_guid = Guid.from_low_guid(:mob, 5, 9)
      summon = Summon.attach_owner(mob(flags: 0), owner_guid)

      assert summon.unit.summoned_by == owner_guid
      assert summon.unit.created_by == owner_guid
      assert summon.unit.flags == 0
    end

    test "ignores non-integer owners" do
      summon = mob(flags: 0)

      assert Summon.attach_owner(summon, nil) == summon
    end
  end

  defp mob(flags: flags) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1, 1)},
      unit: %Unit{flags: flags}
    }
  end
end
