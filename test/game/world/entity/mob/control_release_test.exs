defmodule ThistleTea.Game.World.Entity.Mob.ControlReleaseTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.ControlSync
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.Mob, as: MobServer
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Test.Unique

  @mind_control 10_911
  @enslave_demon 11_726

  @alliance %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}

  @wolf %FactionTemplate{
    id: 32,
    faction: 29,
    flags: 16,
    faction_group: 0,
    friend_group: 0,
    enemy_group: 2,
    enemies_0: 28
  }

  defp controlled(aura_type, spell_id) do
    owner = Guid.from_low_guid(:player, Unique.integer())

    holder = %Holder{
      spell: %Spell{id: spell_id},
      caster_guid: owner,
      caster_faction_template: 35,
      auras: [%Aura{type: aura_type}]
    }

    mob = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 98, Unique.integer())},
      unit: %Unit{auras: [holder], faction_template: 14, health: 300, max_health: 300},
      internal: %Internal{}
    }

    {mob, _events} = ControlSync.sync(mob, 0)
    {owner, mob}
  end

  describe "handle_info/2 release_control" do
    test "frees a mind-controlled creature instead of despawning it" do
      {owner, mob} = controlled(:mod_possess, @mind_control)

      assert {:noreply, released, {:continue, :maybe_broadcast}} =
               MobServer.handle_info({:release_control, owner, @mind_control}, mob)

      assert released.unit.health == 300
      assert released.unit.auras == []
    end

    test "frees a charmed creature named by its control spell" do
      {owner, mob} = controlled(:mod_charm, @enslave_demon)

      for spell_id <- [@enslave_demon, nil] do
        assert {:noreply, released, {:continue, :maybe_broadcast}} =
                 MobServer.handle_info({:release_control, owner, spell_id}, mob)

        assert released.unit.auras == []
      end
    end

    test "ignores releases from anyone but the controller" do
      {_owner, mob} = controlled(:mod_possess, @mind_control)
      stranger = Guid.from_low_guid(:player, Unique.integer())

      assert MobServer.handle_info({:release_control, stranger, @mind_control}, mob) == {:noreply, mob}
    end
  end

  describe "handle_info/2 turn_on_controller" do
    test "a freed hostile creature attacks its former controller with its health as threat" do
      {owner, mob} = released(@wolf)

      assert {:noreply, engaged, {:continue, :maybe_broadcast}} =
               MobServer.handle_info({:turn_on_controller, owner, 300}, mob)

      assert engaged.internal.in_combat
      assert engaged.unit.target == owner
      assert engaged.internal.threat == %{owner => 300.0}
      Process.cancel_timer(engaged.internal.ai_tick_ref)
    end

    test "a freed creature friendly to its former controller stays calm" do
      {owner, mob} = released(@alliance)

      assert MobServer.handle_info({:turn_on_controller, owner, 300}, mob) == {:noreply, mob}
    end
  end

  defp released(faction_template) do
    owner = Guid.from_low_guid(:player, Unique.integer())
    guid = Guid.from_low_guid(:mob, 98, Unique.integer())

    Metadata.put(owner, %{faction_template: @alliance, alive?: true, unit_flags: 0})
    Metadata.put(guid, %{faction_template: faction_template, alive?: true, unit_flags: 0})

    on_exit(fn ->
      Metadata.delete(owner)
      Metadata.delete(guid)
    end)

    mob = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 300, level: 60, auras: []},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    {owner, mob}
  end
end
