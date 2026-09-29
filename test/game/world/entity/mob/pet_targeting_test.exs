defmodule ThistleTea.Game.World.Entity.Mob.PetTargetingTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.BT.Pet, as: PetBT
  alias ThistleTea.Game.Core.Combat.KillFeedback
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Entity.Mob, as: MobServer
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  setup [:entities]

  describe "handle_cast/2 kill_outcome" do
    test "both pet and owner kills select the next victim before death metadata arrives", %{
      pet: pet,
      target: target,
      other: other
    } do
      owner = System.unique_integer([:positive]) + 20_000_000
      pet = %{pet | internal: %{pet.internal | pet: %{pet.internal.pet | owner_guid: owner}}}
      pet = PetBT.command(pet, :attack, target, 1_000)
      Metadata.put(owner, %{in_combat: true, combat_targets: [target, other]})
      SpatialHash.update(:players, owner, pet.internal.world, 0.0, 0.0, 0.0)
      Metadata.update(target, %{in_combat: true, combat_victim_guid: pet.object.guid})
      Metadata.update(other, %{in_combat: true, combat_victim_guid: owner})

      on_exit(fn ->
        Metadata.delete(owner)
        SpatialHash.remove(:players, owner)
      end)

      victim = %KillFeedback.Victim{guid: target, level: 10, reward_target?: true}

      assert {:noreply, continued, {:continue, :maybe_broadcast}} = MobServer.handle_cast({:kill_outcome, victim}, pet)
      assert continued.unit.target == other
      assert continued.internal.in_combat
      refute continued.internal.pet.attack_command?
      Process.cancel_timer(continued.internal.ai_tick_ref)

      assert {:noreply, continued, {:continue, :maybe_broadcast}} =
               MobServer.handle_info({:owner_killed, owner, target}, pet)

      assert continued.unit.target == other
      Process.cancel_timer(continued.internal.ai_tick_ref)
      assert {:noreply, ^pet} = MobServer.handle_info({:owner_killed, owner + 1, target}, pet)
    end
  end

  describe "handle_info/2 pet_attacked" do
    test "core damage reaches the explicit owner context and respects the latest command", %{pet: pet, target: target} do
      damaged = Entity.take_damage(pet, 10, 1_000, source: target)
      assert damaged.unit.health == 90
      assert damaged.internal.in_combat
      effect = Enum.find(damaged.internal.events, &is_struct(&1, Effects.PetAttacked))
      test_pid = self()
      receiver = spawn(fn -> receive do: (message -> send(test_pid, {:delivered, message})) end)
      EventSink.emit(damaged, effect, Context.new(receiver))
      assert_receive {:delivered, {:pet_attacked, ^target} = reaction}
      refute_receive {:pet_attacked, _}, 0

      recalled = PetBT.command(damaged, :follow, 0, 1_001)
      assert {:noreply, ^recalled, {:continue, :maybe_broadcast}} = MobServer.handle_info(reaction, recalled)
      assert {:noreply, defended, {:continue, :maybe_broadcast}} = MobServer.handle_info(reaction, damaged)
      assert defended.unit.target == target
      assert defended.internal.in_combat
      refute defended.internal.pet.attack_command?
      Process.cancel_timer(defended.internal.ai_tick_ref)
    end

    test "death before delivery prevents retaliation", %{pet: pet, target: target} do
      dead = Entity.take_damage(pet, 100, 1_000, source: target)
      assert {:noreply, ^dead, {:continue, :maybe_broadcast}} = MobServer.handle_info({:pet_attacked, target}, dead)
    end
  end

  describe "handle_cast/2 receive_attack" do
    test "Stay takes ranged damage without choosing a victim", %{pet: pet, target: target} do
      pet = PetBT.command(pet, :stay, 0, 1_000)
      attack = attack(target)
      assert {:noreply, damaged, {:continue, :maybe_broadcast}} = MobServer.handle_cast({:receive_attack, attack}, pet)
      assert damaged.unit.health == 90
      assert damaged.internal.in_combat
      assert damaged.unit.target in [nil, 0]
      Process.cancel_timer(damaged.internal.ai_tick_ref)
    end

    test "contact starts defense even when the incoming attack deals no damage", %{pet: pet, target: target} do
      pet = PetBT.command(pet, :stay, 0, 1_000)
      SpatialHash.update(:mobs, target, pet.internal.world, 2.0, 0.0, 0.0)
      attack = %{attack(target) | damage: 0}
      assert {:noreply, defended, {:continue, :maybe_broadcast}} = MobServer.handle_cast({:receive_attack, attack}, pet)
      assert defended.unit.health == 100
      assert defended.internal.in_combat
      assert defended.unit.target == target
      Process.cancel_timer(defended.internal.ai_tick_ref)
    end

    test "zero-damage contact keeps a waiting or passive pet in combat", %{pet: pet, target: target} do
      for reaction <- [:passive, :defensive] do
        waiting = pet |> PetBT.command(:stay, 0, 1_000) |> PetBT.reaction(reaction)
        attack = %{attack(target) | damage: 0}

        assert {:noreply, contacted, {:continue, :maybe_broadcast}} =
                 MobServer.handle_cast({:receive_attack, attack}, waiting)

        assert contacted.unit.health == 100
        assert contacted.internal.in_combat
        assert contacted.unit.target in [nil, 0]
        Process.cancel_timer(contacted.internal.ai_tick_ref)
      end
    end

    test "damage from another attacker keeps the current living victim", %{pet: pet, target: target, other: other} do
      pet = %{pet | unit: %{pet.unit | target: other}, internal: %{pet.internal | in_combat: true}}
      attack = attack(target)
      assert {:noreply, defended, {:continue, :maybe_broadcast}} = MobServer.handle_cast({:receive_attack, attack}, pet)
      assert defended.unit.health == 90
      assert defended.unit.target == other
      Process.cancel_timer(defended.internal.ai_tick_ref)
    end
  end

  describe "handle_info/2 owner_attacked" do
    test "waits for breakable control to end before defending the owner", %{pet: pet, target: target} do
      Metadata.update(target, %{breakable_crowd_control?: true})
      assert {:noreply, ^pet, {:continue, :maybe_broadcast}} = MobServer.handle_info({:owner_attacked, target}, pet)

      Metadata.update(target, %{breakable_crowd_control?: false})
      assert {:noreply, engaged, {:continue, :maybe_broadcast}} = MobServer.handle_info({:owner_attacked, target}, pet)
      assert engaged.unit.target == target
      assert engaged.internal.in_combat
      assert is_reference(engaged.internal.ai_tick_ref)
      Process.cancel_timer(engaged.internal.ai_tick_ref)
    end

    test "Stay rejects a distant attacker and accepts melee contact", %{pet: pet, target: target} do
      pet = %{pet | internal: %{pet.internal | pet: %{pet.internal.pet | command_state: :stay}}}
      assert {:noreply, ^pet, {:continue, :maybe_broadcast}} = MobServer.handle_info({:owner_attacked, target}, pet)

      SpatialHash.update(:mobs, target, pet.internal.world, 2.0, 0.0, 0.0)
      assert {:noreply, engaged, {:continue, :maybe_broadcast}} = MobServer.handle_info({:owner_attacked, target}, pet)
      assert engaged.unit.target == target
      assert engaged.internal.pet.command_state == :stay
      Process.cancel_timer(engaged.internal.ai_tick_ref)
    end

    test "does not replace a living victim", %{pet: pet, target: target, other: other} do
      pet = %{pet | unit: %{pet.unit | target: other}, internal: %{pet.internal | in_combat: true}}
      assert {:noreply, ^pet, {:continue, :maybe_broadcast}} = MobServer.handle_info({:owner_attacked, target}, pet)
    end
  end

  defp attack(target) do
    %{
      caster: target,
      caster_level: 10,
      damage: 10,
      ranged?: true,
      hit_chance_bonus: 100,
      crit_chance: 0,
      block_allowed?: false
    }
  end

  defp entities(_context) do
    guid = Guid.runtime(:pet, 1)
    target = Guid.runtime(:mob, 2)
    other = Guid.runtime(:mob, 2)
    world = WorldRef.open(999)
    alliance = %FactionTemplate{id: 1, faction: 1, faction_group: 3, friend_group: 2, enemy_group: 12}
    hostile = %FactionTemplate{id: 17, faction: 15, faction_group: 8, enemy_group: 1}
    Metadata.put(guid, %{faction_template: alliance, alive?: true})

    for enemy <- [target, other] do
      Metadata.put(enemy, %{faction_template: hostile, alive?: true, level: 10, unit_flags: 0})
      SpatialHash.update(:mobs, enemy, world, 10.0, 0.0, 0.0)
    end

    on_exit(fn ->
      for actor <- [guid, target, other] do
        Metadata.delete(actor)
        SpatialHash.remove(:mobs, actor)
      end
    end)

    pet = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, level: 10, auras: [], combat_reach: 1.5},
      internal: %Internal{world: world, pet: %Pet{kind: :hunter, owner_guid: 1}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{pet: pet, target: target, other: other}
  end
end
