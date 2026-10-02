defmodule ThistleTea.Game.World.Entity.Mob.ControlReleaseTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.ControlSync
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.World.Entity.Mob, as: MobServer
  alias ThistleTea.Test.Unique

  @mind_control 10_911
  @enslave_demon 11_726

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
end
