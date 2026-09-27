defmodule ThistleTea.Game.Entity.Server.Mob.PetTargetingTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet, as: PetBT
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:entities]

  describe "handle_info/2 pet_attacked" do
    test "core damage reaches the explicit owner context and respects the latest command", %{pet: pet, target: target} do
      damaged = Core.take_damage(pet, 10, 1_000, source: target)
      assert damaged.unit.health == 90
      refute damaged.internal.in_combat
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
      dead = Core.take_damage(pet, 100, 1_000, source: target)
      assert {:noreply, ^dead, {:continue, :maybe_broadcast}} = MobServer.handle_info({:pet_attacked, target}, dead)
    end
  end

  describe "handle_cast/2 receive_attack" do
    test "Stay takes ranged damage without choosing a victim", %{pet: pet, target: target} do
      pet = PetBT.command(pet, :stay, 0, 1_000)
      attack = %{caster: target, damage: 10, damage_state: 1, hit_info: 2}
      assert {:noreply, damaged, {:continue, :maybe_broadcast}} = MobServer.handle_cast({:receive_attack, attack}, pet)
      assert damaged.unit.health == 90
      refute damaged.internal.in_combat
      assert damaged.unit.target in [nil, 0]
      Process.cancel_timer(damaged.internal.ai_tick_ref)
    end

    test "contact starts defense even when the incoming attack misses", %{pet: pet, target: target} do
      pet = PetBT.command(pet, :stay, 0, 1_000)
      SpatialHash.update(:mobs, target, pet.internal.world, 2.0, 0.0, 0.0)
      attack = %{caster: target, damage: 0, damage_state: 1, hit_info: 0x10}
      assert {:noreply, defended, {:continue, :maybe_broadcast}} = MobServer.handle_cast({:receive_attack, attack}, pet)
      assert defended.unit.health == 100
      assert defended.internal.in_combat
      assert defended.unit.target == target
      Process.cancel_timer(defended.internal.ai_tick_ref)
    end

    test "damage from another attacker keeps the current living victim", %{pet: pet, target: target, other: other} do
      pet = %{pet | unit: %{pet.unit | target: other}, internal: %{pet.internal | in_combat: true}}
      attack = %{caster: target, damage: 10, damage_state: 1, hit_info: 2}
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
