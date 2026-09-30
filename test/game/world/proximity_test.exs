defmodule ThistleTea.Game.World.ProximityTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.AIEvent
  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Combat.Proximity.Aggressor
  alias ThistleTea.Game.Core.Combat.Proximity.Announcement
  alias ThistleTea.Game.Core.Combat.Proximity.Path
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.GameObject, as: GameObjectComponent
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Trap
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.SpatialGrid
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Groups
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Proximity
  alias ThistleTea.Game.World.Proximity.Checks
  alias ThistleTea.Game.World.SpatialHash

  defp hear(listener, announcement, now), do: elem(Proximity.hear(listener, announcement, now), 1)

  defp due(listener, guid, role, now) do
    announcement = %Announcement{guid: guid, world: listener.internal.world, position: {0.0, 0.0, 0.0}, level: 5}
    listener = Checks.schedule(listener, announcement, role, now + 60_000, now)
    {ref, _, _} = listener.internal.proximity_checks[{guid, role}]
    elem(Proximity.due(listener, guid, role, ref, now), 1)
  end

  describe "hear/3" do
    test "asks a hostile idle creature to notice a listener inside its radius" do
      {player, mob_guid} = hostile_pair({10.0, 0.0, 0.0})

      assert hear(player, creature_announcement(mob_guid, {10.0, 0.0, 0.0}), Time.now()) == :ignore
      assert_receive {:"$gen_cast", {:aggro_probe, guid}}
      assert guid == player.object.guid
    end

    test "uses the creature's published detect range modifier" do
      {player, mob_guid} = hostile_pair({15.0, 0.0, 0.0})
      Metadata.update(mob_guid, %{detect_range_modifier: -10})

      hear(player, creature_announcement(mob_guid, {15.0, 0.0, 0.0}), Time.now())
      refute_receive {:"$gen_cast", {:aggro_probe, _guid}}

      Metadata.update(mob_guid, %{detect_range_modifier: 0})
      hear(player, creature_announcement(mob_guid, {15.0, 0.0, 0.0}), Time.now())
      assert_receive {:"$gen_cast", {:aggro_probe, _guid}}
    end

    test "taxi passengers do not attract creatures until they land" do
      {player, mob_guid} = hostile_pair({10.0, 0.0, 0.0})
      Metadata.update(player.object.guid, %{unit_flags: 0x00100000})

      hear(player, creature_announcement(mob_guid, {10.0, 0.0, 0.0}), Time.now())
      refute_receive {:"$gen_cast", {:aggro_probe, _guid}}

      Metadata.update(player.object.guid, %{unit_flags: 0})
      hear(player, creature_announcement(mob_guid, {10.0, 0.0, 0.0}), Time.now())
      assert_receive {:"$gen_cast", {:aggro_probe, _guid}}
    end

    test "invisibility blocks aggro until the creature has matching detection" do
      {player, mob_guid} = hostile_pair({1.0, 0.0, 0.0})
      Metadata.update(player.object.guid, %{invisibility: %{0 => 200}})

      hear(player, creature_announcement(mob_guid, {1.0, 0.0, 0.0}), Time.now())
      refute_receive {:"$gen_cast", {:aggro_probe, _guid}}

      Metadata.update(mob_guid, %{invisibility_detection: %{0 => 200}})
      hear(player, creature_announcement(mob_guid, {1.0, 0.0, 0.0}), Time.now())
      assert_receive {:"$gen_cast", {:aggro_probe, _guid}}
    end

    test "friendly, neutral, and forced-friendly creatures are not asked" do
      player = player(put_player(player_guid()))
      wolf = put_mob(mob_guid(), {10.0, 0.0, 0.0}, faction_template: wolf())
      hear(player, creature_announcement(wolf, {10.0, 0.0, 0.0}), Time.now())
      refute_receive {:"$gen_cast", {:aggro_probe, _guid}}

      forced =
        player(put_player(player_guid(), reputation: %{15 => %{rank: :hostile, at_war?: true, forced_rank: :friendly}}))

      defias = put_mob(mob_guid(), {10.0, 0.0, 0.0})
      hear(forced, creature_announcement(defias, {10.0, 0.0, 0.0}), Time.now())
      refute_receive {:"$gen_cast", {:aggro_probe, _guid}}
    end

    test "a reputation faction's creatures that hate the player are asked" do
      player = player(put_player(player_guid(), reputation: %{29 => %{rank: :hostile, at_war?: true}}))
      mob_guid = put_mob(mob_guid(), {10.0, 0.0, 0.0}, faction_template: wolf(), faction_can_have_reputation?: true)

      hear(player, creature_announcement(mob_guid, {10.0, 0.0, 0.0}), Time.now())
      assert_receive {:"$gen_cast", {:aggro_probe, _guid}}
    end

    test "creatures that no longer aggro on sight are not asked" do
      player = player(put_player(player_guid()))
      passive = put_mob(mob_guid(), {10.0, 0.0, 0.0}, proximity_aggro?: false)
      fighting = put_mob(mob_guid(), {10.0, 0.0, 0.0}, in_combat: true)
      dead = put_mob(mob_guid(), {10.0, 0.0, 0.0}, alive?: false)

      for guid <- [passive, fighting, dead] do
        hear(player, creature_announcement(guid, {10.0, 0.0, 0.0}), Time.now())
      end

      refute_receive {:"$gen_cast", {:aggro_probe, _guid}}
    end

    test "listeners beyond the level-scaled radius or dead are not offered" do
      {player, mob_guid} = hostile_pair({30.0, 0.0, 0.0})
      hear(player, creature_announcement(mob_guid, {30.0, 0.0, 0.0}), Time.now())
      refute_receive {:"$gen_cast", {:aggro_probe, _guid}}

      ghost = player(put_player(player_guid(), alive?: false))
      hear(ghost, creature_announcement(mob_guid, {10.0, 0.0, 0.0}), Time.now())
      refute_receive {:"$gen_cast", {:aggro_probe, _guid}}
    end

    test "stealth uses detection distance and the creature's detection bonus" do
      stealthed = player(put_player(player_guid(), stealthed?: true, stealth_skill: 25))
      mob_guid = put_mob(mob_guid(), {5.0, 0.0, 0.0})

      hear(stealthed, creature_announcement(mob_guid, {5.0, 0.0, 0.0}), Time.now())
      refute_receive {:"$gen_cast", {:aggro_probe, _guid}}

      Metadata.update(mob_guid, %{stealth_detection_bonus: 30})
      hear(stealthed, creature_announcement(mob_guid, {5.0, 0.0, 0.0}), Time.now())
      assert_receive {:"$gen_cast", {:aggro_probe, _guid}}

      vanished = player(put_player(player_guid(), undetectable_until: Time.now() + 1_000))
      hear(vanished, creature_announcement(mob_guid, {0.5, 0.0, 0.0}), Time.now())
      refute_receive {:"$gen_cast", {:aggro_probe, _guid}}
    end

    test "an idle creature notices a hostile announcer inside its radius" do
      player_guid = put_player(player_guid())
      mob = mob(put_mob(mob_guid(), {0.0, 0.0, 0.0}))

      assert hear(mob, player_announcement(player_guid, {10.0, 0.0, 0.0}), Time.now()) == :notice
      assert hear(mob, player_announcement(player_guid, {30.0, 0.0, 0.0}), Time.now()) == :ignore

      wolf = mob(put_mob(mob_guid(), {0.0, 0.0, 0.0}, faction_template: wolf()))
      assert hear(wolf, player_announcement(player_guid, {10.0, 0.0, 0.0}), Time.now()) == :ignore

      fighting = %{mob | internal: %{mob.internal | in_combat: true}}
      assert hear(fighting, player_announcement(player_guid, {10.0, 0.0, 0.0}), Time.now()) == :ignore
      assert hear(mob, creature_announcement(mob.object.guid, {0.0, 0.0, 0.0}), Time.now()) == :ignore
    end

    test "a creature with an out-of-combat sight event wakes for announcers in range" do
      player_guid = put_player(player_guid())
      greeter = mob(put_mob(mob_guid(), {0.0, 0.0, 0.0}, faction_template: wolf()))
      sight = %AIEvent{event_type: :ooc_los, param2: 20}
      creature = %{greeter.internal.creature | ai_events: [sight]}
      greeter = %{greeter | internal: %{greeter.internal | creature: creature}}

      assert hear(greeter, player_announcement(player_guid, {10.0, 0.0, 0.0}), Time.now()) == :sight
      assert hear(greeter, player_announcement(player_guid, {30.0, 0.0, 0.0}), Time.now()) == :ignore

      fighting = %{greeter | internal: %{greeter.internal | in_combat: true}}
      assert hear(fighting, player_announcement(player_guid, {10.0, 0.0, 0.0}), Time.now()) == :ignore
    end

    test "a walking announcer schedules one check for the moment of contact" do
      player_guid = put_player(player_guid())
      mob = mob(put_mob(mob_guid(), {0.0, 0.0, 0.0}))
      now = Time.now()
      path = %Path{origin: {100.0, 0.0, 0.0}, nodes: [{0.0, 0.0, 0.0}], started_at: now, duration_ms: 1_000}
      announcement = %{player_announcement(player_guid, {100.0, 0.0, 0.0}) | path: path}

      assert hear(mob, announcement, now) == :ignore
      refute_received {:timeout, _ref, {:proximity_due, _guid, _role}}
      assert_receive {:timeout, _ref, {:proximity_due, ^player_guid, :notice}}, 1_000
    end
  end

  describe "due/5" do
    test "coalesces duplicates and rejects cancelled callbacks" do
      guid = put_player(player_guid())
      mob = mob(put_mob(mob_guid(), {0.0, 0.0, 0.0}))
      now = Time.now()
      path = %Path{origin: {100.0, 0.0, 0.0}, nodes: [{0.0, 0.0, 0.0}], started_at: now, duration_ms: 60_000}
      announcement = %{player_announcement(guid, path.origin) | path: path}
      {mob, :ignore} = Proximity.hear(mob, announcement, now)
      checks = mob.internal.proximity_checks

      mob = Enum.reduce(1..100, mob, fn _, mob -> elem(Proximity.hear(mob, announcement, now), 0) end)
      assert mob.internal.proximity_checks == checks
      assert map_size(checks) == 1
      {old_ref, _, _} = checks[{guid, :notice}]

      changed = %{announcement | path: %{path | duration_ms: 30_000}}
      {mob, :ignore} = Proximity.hear(mob, changed, now)
      {new_ref, _, _} = mob.internal.proximity_checks[{guid, :notice}]
      assert new_ref != old_ref
      assert :erlang.read_timer(old_ref) == false
      assert Proximity.due(mob, guid, :notice, old_ref, now) == {mob, :ignore}

      {mob, :notice} = Proximity.hear(mob, player_announcement(guid, {8.0, 0.0, 0.0}), now)
      assert mob.internal.proximity_checks == %{}
      assert :erlang.read_timer(new_ref) == false
      assert Proximity.due(mob, guid, :notice, new_ref, now) == {mob, :ignore}
    end

    test "leaving cancels contact and hidden refresh timers" do
      guid = put_player(player_guid())
      mob = mob(put_mob(mob_guid(), {0.0, 0.0, 0.0})) |> join()
      now = Time.now()
      path = %Path{origin: {100.0, 0.0, 0.0}, nodes: [{0.0, 0.0, 0.0}], started_at: now, duration_ms: 60_000}
      {mob, :ignore} = Proximity.hear(mob, %{player_announcement(guid, path.origin) | path: path}, now)
      {ref, _, _} = mob.internal.proximity_checks[{guid, :notice}]
      left = Proximity.leave(mob, mob.internal.visibility_cell)
      assert left.internal.proximity_checks == %{}
      assert :erlang.read_timer(ref) == false
      assert Proximity.due(left, guid, :notice, ref, now) == {left, :ignore}
    end

    test "rechecks the authoritative position before noticing" do
      player_guid = put_player(player_guid())
      mob = mob(put_mob(mob_guid(), {0.0, 0.0, 0.0}))

      SpatialHash.update(:players, player_guid, WorldRef.open(0), 40.0, 0.0, 0.0)
      assert due(mob, player_guid, :notice, Time.now()) == :ignore

      SpatialHash.update(:players, player_guid, WorldRef.open(0), 8.0, 0.0, 0.0)
      assert due(mob, player_guid, :notice, Time.now()) == :notice
    end

    test "asks the creature to notice a listener it has reached" do
      {player, mob_guid} = hostile_pair({8.0, 0.0, 0.0})

      assert due(player, mob_guid, :alert, Time.now()) == :ignore
      assert_receive {:"$gen_cast", {:aggro_probe, guid}}
      assert guid == player.object.guid
    end
  end

  describe "sync/2" do
    test "announces stationary changes to every detection fact" do
      player = player_guid() |> put_player() |> player() |> join() |> Proximity.sync(Time.now())
      assert_receive {:proximity, %Announcement{}}

      Enum.reduce(
        [stealth_detection_bonus: 30, stalked_by: [123], detects_all_invisibility?: true],
        player,
        fn {key, value}, player ->
          Metadata.update(player.object.guid, %{key => value})
          player = Proximity.sync(player, Time.now())
          assert_receive {:proximity, %Announcement{}}
          player
        end
      )
    end

    test "announces a unit when it moves two yards or changes how others react to it" do
      player = player_guid() |> put_player() |> player() |> join()

      player = Proximity.sync(player, Time.now())
      guid = player.object.guid
      assert_receive {:proximity, %Announcement{guid: ^guid, position: {+0.0, +0.0, +0.0}, level: 5}}

      player = player |> move({1.5, 0.0, 0.0}) |> Proximity.sync(Time.now())
      refute_receive {:proximity, %Announcement{}}

      player = player |> move({2.5, 0.0, 0.0}) |> Proximity.sync(Time.now())
      assert_receive {:proximity, %Announcement{guid: ^guid, position: {2.5, +0.0, +0.0}}}

      Metadata.update(guid, %{alive?: false})
      player = Proximity.sync(player, Time.now())
      assert_receive {:proximity, %Announcement{guid: ^guid}}

      assert Proximity.sync(player, Time.now()) == player
      refute_receive {:proximity, %Announcement{}}
    end

    test "a unit nobody can target stays quiet while it moves" do
      guid = put_player(player_guid())
      Metadata.update(guid, %{unit_flags: 0x00100000})
      player = guid |> player() |> join() |> Proximity.sync(Time.now())
      assert_receive {:proximity, %Announcement{guid: ^guid}}

      player = player |> move({30.0, 0.0, 0.0}) |> Proximity.sync(Time.now())
      refute_receive {:proximity, %Announcement{}}

      Metadata.update(guid, %{unit_flags: 0})
      Proximity.sync(player, Time.now())
      assert_receive {:proximity, %Announcement{guid: ^guid, position: {30.0, +0.0, +0.0}}}
    end

    test "leaving forgets the last announcement so the next entry announces again" do
      player = player_guid() |> put_player() |> player() |> join()
      player = Proximity.sync(player, Time.now())
      assert_receive {:proximity, %Announcement{}}

      cell = player.internal.visibility_cell
      left = Proximity.leave(player, cell)
      assert left.internal.proximity == nil
      Proximity.sync(player, Time.now())
      refute_receive {:proximity, %Announcement{}}

      left |> Proximity.join(cell) |> Proximity.sync(Time.now())
      assert_receive {:proximity, %Announcement{}}
    end

    test "a stealthed unit is listed as hidden and its announcements are marked hidden" do
      guid = put_player(player_guid(), stealthed?: true)
      player = guid |> player() |> join()
      cell = player.internal.visibility_cell
      assert Proximity.hidden_members([cell]) == [guid]

      player = Proximity.sync(player, Time.now())
      assert_receive {:proximity, %Announcement{guid: ^guid, hidden?: true}}

      Metadata.update(guid, %{stealthed?: false})
      player = Proximity.sync(player, Time.now())
      assert_receive {:proximity, %Announcement{guid: ^guid, hidden?: false}}
      assert Proximity.hidden_members([cell]) == []

      Metadata.update(guid, %{stealthed?: true})
      player = Proximity.sync(player, Time.now())
      assert Proximity.hidden_members([cell]) == [guid]
      assert Proximity.leave(player, cell).internal.hidden_cell == nil
      assert Proximity.hidden_members([cell]) == []
    end

    test "a reaction change tells the traps the unit owns" do
      guid = put_player(player_guid())
      player = guid |> player() |> join() |> Proximity.sync(Time.now())
      :ok = Group.join(Groups, Proximity.owned_key(guid), %{})

      Metadata.update(guid, %{duel_started?: true})
      synced = Proximity.sync(player, Time.now())
      assert Proximity.reaction_changed?(player, synced)
      assert_receive {:owner_reaction_changed, ^guid}

      Metadata.update(guid, %{level: 6})
      leveled = Proximity.sync(synced, Time.now())
      refute Proximity.reaction_changed?(synced, leveled)
      refute_receive {:owner_reaction_changed, _guid}
    end
  end

  describe "refresh/3" do
    test "an undetectable unit announces again the moment that ends" do
      guid = put_player(player_guid(), undetectable_until: Time.now() + 30)
      player = guid |> player() |> join() |> Proximity.sync(Time.now())
      assert_receive {:proximity, %Announcement{guid: ^guid, hidden?: false}}
      assert {ref, _at} = player.internal.proximity_refresh

      assert_receive {:timeout, ^ref, :proximity_refresh}, 500
      assert Proximity.refresh(player, make_ref(), Time.now()) == player
      refute_receive {:proximity, %Announcement{}}

      refreshed = Proximity.refresh(player, ref, Time.now())
      assert_receive {:proximity, %Announcement{guid: ^guid, hidden?: true}}
      assert refreshed.internal.proximity_refresh == nil
    end

    test "a stealthed walker keeps announcing every two yards until it arrives" do
      guid = put_player(player_guid(), stealthed?: true)
      now = Time.now()
      player = guid |> player() |> walk({40.0, 0.0, 0.0}, now, 4_000) |> join() |> Proximity.sync(now)
      assert_receive {:proximity, %Announcement{guid: ^guid, hidden?: true}}
      assert {_ref, at} = player.internal.proximity_refresh
      assert at == now + 200

      Metadata.update(guid, %{stealthed?: false})
      unhidden = Proximity.sync(player, now)
      assert unhidden.internal.proximity_refresh == nil
    end
  end

  describe "join/2" do
    test "stealthed traps are listed as hidden and join their owner's owned key" do
      owner = player_guid()
      trap = trap(owner, true)
      cell = SpatialGrid.cell(WorldRef.open(0), 0.0, 0.0, 0.0)

      joined = Proximity.join(trap, cell)
      assert Proximity.hidden_members([cell]) == [trap.object.guid]
      assert [{pid, _meta}] = Group.members(Groups, Proximity.owned_key(owner))
      assert pid == self()

      Proximity.leave(joined, cell)
      assert Proximity.hidden_members([cell]) == []
      assert Group.members(Groups, Proximity.owned_key(owner)) == []

      assert Proximity.join(trap(owner, false), cell).internal.hidden_cell == nil
      assert Proximity.hidden_members([cell]) == []
    end
  end

  defp hostile_pair(mob_position) do
    {player(put_player(player_guid())), put_mob(mob_guid(), mob_position)}
  end

  defp join(%{internal: %Internal{} = internal} = character) do
    cell = SpatialGrid.cell(internal.world, 0.0, 0.0, 0.0)
    Proximity.join(%{character | internal: %{internal | visibility_cell: cell}}, cell)
  end

  defp move(%Character{movement_block: movement_block} = character, {x, y, z}) do
    %{character | movement_block: %{movement_block | position: {x, y, z, 0.0}}}
  end

  defp walk(%Character{internal: internal, movement_block: movement_block} = character, destination, now, duration) do
    %{
      character
      | internal: %{internal | movement_start_time: now, movement_start_position: {0.0, 0.0, 0.0}},
        movement_block: %{movement_block | spline_nodes: [destination], duration: duration}
    }
  end

  defp trap(owner, stealthed?) do
    %GameObject{
      object: %Object{guid: Guid.from_low_guid(:game_object, 1, System.unique_integer([:positive]))},
      game_object: %GameObjectComponent{created_by: owner},
      internal: %Internal{world: WorldRef.open(0), trap: %Trap{stealthed?: stealthed?}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp creature_announcement(guid, position) do
    %Announcement{
      guid: guid,
      world: WorldRef.open(0),
      position: position,
      level: 5,
      aggressor: %Aggressor{detection_range: 20.0, level: 5, modifier: 0}
    }
  end

  defp player_announcement(guid, position) do
    %Announcement{guid: guid, world: WorldRef.open(0), position: position, level: 5}
  end

  defp player(guid) do
    %Character{
      object: %Object{guid: guid},
      unit: %Unit{level: 5, health: 100, max_health: 100},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp mob(guid) do
    %Mob{
      object: %Object{guid: guid},
      unit: %Unit{level: 5, health: 100, max_health: 100, faction_template: 17, flags: 0},
      internal: %Internal{world: WorldRef.open(0), in_combat: false, creature: %Creature{detection_range: 20.0}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp put_player(guid, opts \\ []) do
    Metadata.put(guid, %{
      alive?: Keyword.get(opts, :alive?, true),
      faction_template: alliance(),
      unit_flags: 0,
      level: 5,
      stealthed?: Keyword.get(opts, :stealthed?, false),
      stealth_skill: Keyword.get(opts, :stealth_skill, 0),
      undetectable_until: Keyword.get(opts, :undetectable_until),
      reputation: Keyword.get(opts, :reputation, %{})
    })

    on_exit(fn ->
      SpatialHash.remove(:players, guid)
      Metadata.delete(guid)
    end)

    guid
  end

  defp put_mob(guid, {x, y, z}, opts \\ []) do
    Entity.register(guid)
    SpatialHash.update(:mobs, guid, WorldRef.open(0), x, y, z)

    Metadata.put(guid, %{
      alive?: Keyword.get(opts, :alive?, true),
      in_combat: Keyword.get(opts, :in_combat, false),
      faction_template: Keyword.get(opts, :faction_template, defias()),
      unit_flags: 0,
      level: 5,
      proximity_aggro?: Keyword.get(opts, :proximity_aggro?, true),
      faction_can_have_reputation?: Keyword.get(opts, :faction_can_have_reputation?, false)
    })

    on_exit(fn ->
      Entity.unregister(guid)
      SpatialHash.remove(:mobs, guid)
      Metadata.delete(guid)
    end)

    guid
  end

  defp player_guid, do: Guid.from_low_guid(:player, System.unique_integer([:positive]))

  defp mob_guid, do: Guid.from_low_guid(:mob, 1, System.unique_integer([:positive]))

  defp alliance do
    %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}
  end

  defp defias do
    %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, friend_group: 0, enemy_group: 1, friends_0: 15}
  end

  defp wolf do
    %FactionTemplate{id: 32, faction: 29, flags: 16, faction_group: 0, friend_group: 0, enemy_group: 0, enemies_0: 28}
  end
end
