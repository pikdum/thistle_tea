defmodule ThistleTea.Game.Entity.Logic.PlayerCombatTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  @unit_flag_in_combat 0x00080000

  describe "mark_attacked/2" do
    test "sets the combat flag and the hostile timestamp" do
      character = PlayerCombat.mark_attacked(character(), 1_000)

      assert character.internal.in_combat == true
      assert character.internal.last_hostile_time == 1_000
      assert Bitwise.band(character.unit.flags, @unit_flag_in_combat) == @unit_flag_in_combat
    end
  end

  describe "mark_initiated/2" do
    test "sets the combat flag and the hostile timestamp" do
      character = PlayerCombat.mark_initiated(character(), 1_000)

      assert character.internal.in_combat == true
      assert character.internal.last_hostile_time == 1_000
      assert Bitwise.band(character.unit.flags, @unit_flag_in_combat) == @unit_flag_in_combat
    end
  end

  describe "sync/3" do
    test "stays in combat within the drop window of the last hostile event" do
      character = character(in_combat: true, last_hostile_time: 1_000)

      {character, _blackboard} = PlayerCombat.sync(character, %Blackboard{}, 3_000)

      assert character.internal.in_combat == true
    end

    test "drops combat once the drop window lapses" do
      character = character(in_combat: true, last_hostile_time: 1_000)

      {character, _blackboard} = PlayerCombat.sync(character, %Blackboard{}, 7_000)

      assert character.internal.in_combat == false
      assert Bitwise.band(character.unit.flags, @unit_flag_in_combat) == 0
    end

    test "drops combat after the window even with a nonzero attacker_count" do
      character = character(in_combat: true, last_hostile_time: 1_000)
      Metadata.put(character.object.guid, %{attacker_count: 5})

      on_exit(fn -> Metadata.delete(character.object.guid) end)

      {character, _blackboard} = PlayerCombat.sync(character, %Blackboard{}, 7_000)

      assert character.internal.in_combat == false
    end

    test "keeps combat and refreshes the timer while auto-attacking a live target" do
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      SpatialHash.update(:mobs, target_guid, 0, 1.0, 0.0, 0.0)
      Metadata.put(target_guid, %{alive?: true})

      character = character(in_combat: true, target: target_guid, last_hostile_time: 1_000)

      on_exit(fn ->
        SpatialHash.remove(:mobs, target_guid)
        Metadata.delete(target_guid)
      end)

      {character, blackboard} = PlayerCombat.sync(character, %Blackboard{auto_attacking: true}, 100_000)

      assert character.internal.in_combat == true
      assert character.internal.last_hostile_time == 100_000
      assert blackboard.auto_attacking == true
    end

    test "stops swinging a dead target but lingers in combat, then drops after the window" do
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      SpatialHash.update(:mobs, target_guid, 0, 1.0, 0.0, 0.0)
      Metadata.put(target_guid, %{alive?: false})

      character = character(in_combat: true, target: target_guid, last_hostile_time: 1_000)

      on_exit(fn ->
        SpatialHash.remove(:mobs, target_guid)
        Metadata.delete(target_guid)
      end)

      blackboard = %Blackboard{auto_attacking: true, attack_started: true, next_attack_at: 1_500}
      {character, blackboard} = PlayerCombat.sync(character, blackboard, 3_000)

      assert character.internal.in_combat == true
      assert blackboard.auto_attacking == false
      assert blackboard.next_attack_at == 1_500

      {character, _blackboard} = PlayerCombat.sync(character, %Blackboard{auto_attacking: false}, 7_000)

      assert character.internal.in_combat == false
    end

    test "does not keep combat for a selected but un-engaged target once the window lapses" do
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      SpatialHash.update(:mobs, target_guid, 0, 1.0, 0.0, 0.0)
      Metadata.put(target_guid, %{alive?: true})

      character = character(in_combat: true, target: target_guid, last_hostile_time: 1_000)

      on_exit(fn ->
        SpatialHash.remove(:mobs, target_guid)
        Metadata.delete(target_guid)
      end)

      {character, _blackboard} = PlayerCombat.sync(character, %Blackboard{auto_attacking: false}, 7_000)

      assert character.internal.in_combat == false
    end
  end

  defp character(opts \\ []) do
    %Character{
      object: %Object{guid: Guid.from_low_guid(:player, unique_guid())},
      unit: %Unit{target: Keyword.get(opts, :target, 0)},
      internal: %Internal{
        map: 0,
        in_combat: Keyword.get(opts, :in_combat, false),
        last_hostile_time: Keyword.get(opts, :last_hostile_time)
      }
    }
  end

  defp unique_guid do
    System.unique_integer([:positive, :monotonic])
  end
end
