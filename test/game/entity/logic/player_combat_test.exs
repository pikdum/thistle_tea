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

  describe "mark_attacked/2" do
    test "sets the player combat flag and hostile timestamp" do
      character = character()

      character = PlayerCombat.mark_attacked(character, 1_000)

      assert character.internal.in_combat == true
      assert character.internal.last_hostile_time == 1_000
    end
  end

  describe "sync/2" do
    test "keeps combat while attackers are targeting the player" do
      character = character(in_combat: true)
      Metadata.put(character.object.guid, %{attacker_count: 1})

      on_exit(fn -> Metadata.delete(character.object.guid) end)

      {character, blackboard} = PlayerCombat.sync(character, %Blackboard{attack_started: true, next_attack_at: 1_500})

      assert character.internal.in_combat == true
      assert blackboard.attack_started == true
      assert blackboard.next_attack_at == 1_500
    end

    test "clears combat and attack timing once nothing is fighting the player" do
      character = character(in_combat: true)
      Metadata.put(character.object.guid, %{attacker_count: 0})

      on_exit(fn -> Metadata.delete(character.object.guid) end)

      {character, blackboard} = PlayerCombat.sync(character, %Blackboard{attack_started: true, next_attack_at: 1_500})

      assert character.internal.in_combat == false
      assert blackboard.attack_started == false
      assert blackboard.next_attack_at == 0
    end

    test "does not keep combat for a selected target without auto attack" do
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      SpatialHash.update(:mobs, target_guid, 0, 1.0, 0.0, 0.0)
      Metadata.put(target_guid, %{alive?: true})

      character = character(in_combat: true, target: target_guid)
      Metadata.put(character.object.guid, %{attacker_count: 0})

      on_exit(fn ->
        SpatialHash.remove(:mobs, target_guid)
        Metadata.delete(target_guid)
        Metadata.delete(character.object.guid)
      end)

      {character, _blackboard} = PlayerCombat.sync(character, %Blackboard{auto_attacking: false})

      assert character.internal.in_combat == false
    end

    test "keeps combat for an active auto attack target" do
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      SpatialHash.update(:mobs, target_guid, 0, 1.0, 0.0, 0.0)
      Metadata.put(target_guid, %{alive?: true})

      character = character(in_combat: true, target: target_guid)
      Metadata.put(character.object.guid, %{attacker_count: 0})

      on_exit(fn ->
        SpatialHash.remove(:mobs, target_guid)
        Metadata.delete(target_guid)
        Metadata.delete(character.object.guid)
      end)

      {character, blackboard} = PlayerCombat.sync(character, %Blackboard{auto_attacking: true})

      assert character.internal.in_combat == true
      assert blackboard.auto_attacking == true
    end
  end

  defp character(opts \\ []) do
    %Character{
      object: %Object{guid: Guid.from_low_guid(:player, unique_guid())},
      unit: %Unit{target: Keyword.get(opts, :target, 0)},
      internal: %Internal{map: 0, in_combat: Keyword.get(opts, :in_combat, false)}
    }
  end

  defp unique_guid do
    System.unique_integer([:positive, :monotonic])
  end
end
