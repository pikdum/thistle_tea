defmodule ThistleTea.Game.Core.Creature.CreatureLinkTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias ThistleTea.Game.Core.Creature.CreatureLink

  @idle %{present?: true, alive?: true, combat?: false}
  @fighting %{present?: true, alive?: true, combat?: true}
  @dead %{present?: true, alive?: false, combat?: false}

  describe "slave_command/3" do
    test "an aggro-linked slave joins its master's fight once" do
      assert CreatureLink.slave_command(link(0x1), {:attack, 7}, @idle) == {:attack, 7}
      assert CreatureLink.slave_command(link(0x1), {:attack, 7, 3}, @idle) == {:attack, 7}
      assert CreatureLink.slave_command(link(0x1), {:attack, 7}, @fighting) == nil
      assert CreatureLink.slave_command(link(0x1), {:attack, 7}, @dead) == nil
      assert CreatureLink.slave_command(link(0x2), {:attack, 7}, @idle) == nil
    end

    test "a master's evade despawns, evades, or raises its slaves by flag" do
      assert CreatureLink.slave_command(link(0x1000), :evade, @fighting) == :despawn
      assert CreatureLink.slave_command(link(0x4000), :evade, @fighting) == :evade
      assert CreatureLink.slave_command(link(0x4000), :evade, @idle) == nil
      assert CreatureLink.slave_command(link(0x4), :evade, @dead) == :respawn
      assert CreatureLink.slave_command(link(0x4), :evade, @idle) == nil
    end

    test "a master's respawn raises or removes its slaves, and its despawn takes them along" do
      assert CreatureLink.slave_command(link(0x80), :respawn, @dead) == :respawn
      assert CreatureLink.slave_command(link(0x80), :respawn, @idle) == nil
      assert CreatureLink.slave_command(link(0x100), :respawn, @idle) == :despawn
      assert CreatureLink.slave_command(link(0x2000), :despawn, @idle) == :despawn
      assert CreatureLink.slave_command(link(0x2000), :despawn, @dead) == nil
    end

    test "a master's death passes nothing on, as in vmangos" do
      assert CreatureLink.slave_command(link(0x10 ||| 0x20 ||| 0x40), :death, @idle) == nil
    end
  end

  describe "master_command/3" do
    test "a slave pulls its master in and raises it on evade only when flagged to" do
      assert CreatureLink.master_command(link(0x2), {:attack, 7}, @idle) == {:attack, 7}
      assert CreatureLink.master_command(link(0x1), {:attack, 7}, @idle) == nil
      assert CreatureLink.master_command(link(0x8), :evade, @dead) == :respawn
      assert CreatureLink.master_command(link(0x8), :evade, @idle) == nil
    end
  end

  describe "spawn_allowed?/2" do
    test "follows the master's life, or allows the spawn when the master is unknown" do
      assert CreatureLink.spawn_allowed?(link(0x400), @idle)
      refute CreatureLink.spawn_allowed?(link(0x400), @dead)
      refute CreatureLink.spawn_allowed?(link(0x800), @idle)
      assert CreatureLink.spawn_allowed?(link(0x800), @dead)
      refute CreatureLink.spawn_allowed?(link(0xC00), @dead)
      assert CreatureLink.spawn_allowed?(link(0x400), nil)
      assert CreatureLink.spawn_allowed?(link(0x400), %{@dead | present?: false})
      assert CreatureLink.spawn_allowed?(link(0x1), @dead)
    end
  end

  defp link(flags), do: %CreatureLink{slave: 2, master: 1, flags: flags}
end
