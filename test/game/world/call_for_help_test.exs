defmodule ThistleTea.Game.World.CallForHelpTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.CallForHelp
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  describe "assist/2" do
    test "recruits a same-faction helper in range against the attacker" do
      {caller, enemy_guid} = combat_scene()
      helper_guid = put_helper({5.0, 0.0, 0.0})

      CallForHelp.assist(caller, enemy_guid)

      assert_receive {:"$gen_cast", {:assist_attack, ^enemy_guid}}
      _ = helper_guid
    end

    test "requires the same faction template, not mere friendliness" do
      {caller, enemy_guid} = combat_scene()
      put_helper({5.0, 0.0, 0.0}, faction_template: defias_ally())

      CallForHelp.assist(caller, enemy_guid)

      refute_receive {:"$gen_cast", {:assist_attack, _target}}
    end

    test "skips helpers beyond the assistance radius" do
      {caller, enemy_guid} = combat_scene()
      put_helper({15.0, 0.0, 0.0})

      CallForHelp.assist(caller, enemy_guid)

      refute_receive {:"$gen_cast", {:assist_attack, _target}}
    end

    test "skips factions that do not respond to calls for help" do
      {caller, enemy_guid} = combat_scene()
      put_helper({5.0, 0.0, 0.0}, faction_template: wild_animal())

      CallForHelp.assist(caller, enemy_guid)

      refute_receive {:"$gen_cast", {:assist_attack, _target}}
    end

    test "skips factions that flee from calls for help" do
      {caller, enemy_guid} = combat_scene()
      put_helper({5.0, 0.0, 0.0}, faction_template: fleeing_trogg())

      CallForHelp.assist(caller, enemy_guid)

      refute_receive {:"$gen_cast", {:assist_attack, _target}}
    end

    test "skips dead helpers and pets" do
      {caller, enemy_guid} = combat_scene()
      put_helper({5.0, 0.0, 0.0}, alive?: false)
      put_helper({6.0, 0.0, 0.0}, owner_guid: 123)

      CallForHelp.assist(caller, enemy_guid)

      refute_receive {:"$gen_cast", {:assist_attack, _target}}
    end

    test "skips helpers friendly to the enemy" do
      {caller, enemy_guid} = combat_scene()
      put_helper({5.0, 0.0, 0.0}, faction_template: defias_but_alliance_friend())

      CallForHelp.assist(caller, enemy_guid)

      refute_receive {:"$gen_cast", {:assist_attack, _target}}
    end
  end

  describe "pulse/2" do
    test "recruits friendly helpers of other factions within call_for_help_range" do
      {caller, enemy_guid} = combat_scene(range: 5.0)
      put_helper({4.0, 0.0, 0.0}, faction_template: defias_ally())

      CallForHelp.pulse(caller, enemy_guid)

      assert_receive {:"$gen_cast", {:assist_attack, ^enemy_guid}}
    end

    test "respects the template call_for_help_range" do
      {caller, enemy_guid} = combat_scene(range: 5.0)
      put_helper({8.0, 0.0, 0.0})

      CallForHelp.pulse(caller, enemy_guid)

      refute_receive {:"$gen_cast", {:assist_attack, _target}}
    end

    test "does nothing when the range is disabled" do
      {caller, enemy_guid} = combat_scene(range: 0.0)
      put_helper({2.0, 0.0, 0.0})

      CallForHelp.pulse(caller, enemy_guid)

      refute_receive {:"$gen_cast", {:assist_attack, _target}}
    end
  end

  defp combat_scene(opts \\ []) do
    caller_guid = mob_guid()
    enemy_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))

    Metadata.put(caller_guid, %{faction_template: defias()})
    Metadata.put(enemy_guid, %{alive?: true, faction_template: alliance(), unit_flags: 0})

    on_exit(fn ->
      Metadata.delete(caller_guid)
      Metadata.delete(enemy_guid)
    end)

    caller = %Mob{
      object: %Object{guid: caller_guid},
      unit: %Unit{target: enemy_guid, level: 10},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: %WorldRef{map_id: 0},
        creature: %Creature{call_for_help_range: Keyword.get(opts, :range, 5.0)}
      }
    }

    {caller, enemy_guid}
  end

  defp put_helper({x, y, z}, opts \\ []) do
    helper_guid = mob_guid()
    Entity.register(helper_guid)
    SpatialHash.update(:mobs, helper_guid, 0, x, y, z)

    Metadata.put(helper_guid, %{
      alive?: Keyword.get(opts, :alive?, true),
      faction_template: Keyword.get(opts, :faction_template, defias()),
      unit_flags: 0,
      owner_guid: Keyword.get(opts, :owner_guid)
    })

    on_exit(fn ->
      Entity.unregister(helper_guid)
      SpatialHash.remove(:mobs, helper_guid)
      Metadata.delete(helper_guid)
    end)

    helper_guid
  end

  defp mob_guid do
    Guid.from_low_guid(:mob, 1, System.unique_integer([:positive]))
  end

  defp alliance do
    %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}
  end

  defp defias do
    %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, friend_group: 0, enemy_group: 1, friends_0: 15}
  end

  defp defias_ally do
    %FactionTemplate{id: 92, faction: 88, flags: 1, faction_group: 8, friend_group: 0, enemy_group: 1, friends_0: 15}
  end

  defp defias_but_alliance_friend do
    %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, friend_group: 2, enemy_group: 1, friends_0: 15}
  end

  defp wild_animal do
    %FactionTemplate{id: 32, faction: 29, flags: 16, faction_group: 0, friend_group: 0, enemy_group: 0}
  end

  defp fleeing_trogg do
    %FactionTemplate{
      id: 36,
      faction: 45,
      flags: 0x401,
      faction_group: 8,
      friend_group: 0,
      enemy_group: 1,
      friends_0: 15
    }
  end
end
