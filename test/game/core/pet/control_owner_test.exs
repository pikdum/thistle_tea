defmodule ThistleTea.Game.Core.Pet.ControlOwnerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Combat.AttackTable
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.Internal.Totem
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.ControlOwner
  alias ThistleTea.Game.Core.Pet.Possession
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext

  describe "guid/1" do
    test "combat snapshots follow the current controller for every companion kind" do
      guid = Guid.from_low_guid(:mob, 1, 1)
      mob = %Mob{object: %Object{guid: guid}, unit: %Unit{level: 10}}

      for {internal, owner} <- [
            {%Internal{}, guid},
            {%Internal{pet: %Pet{owner_guid: 7}}, 7},
            {%Internal{totem: %Totem{owner_guid: 8}}, 8},
            {%Internal{possession: %Possession{caster_guid: 9, spell_id: 1, original_faction_template: 1}}, 9}
          ] do
        actor = %{mob | internal: internal}
        assert ControlOwner.guid(actor) == owner
        assert AttackTable.attacker_context(actor).caster_owner_guid == owner
        assert CastContext.from_caster(actor, %Spell{id: 1}, 10).caster_owner_guid == owner
        controlled = %{actor | unit: %{actor.unit | charmed_by: 11}}
        assert ControlOwner.guid(controlled) == 11
        assert AttackTable.attacker_context(controlled).caster_owner_guid == 11
        assert CastContext.from_caster(controlled, %Spell{id: 1}, 10).caster_owner_guid == 11
      end
    end

    test "NPC-controlled players retain their controller in melee and spells" do
      npc = Guid.from_low_guid(:mob, 1, 1)

      player = %Character{
        object: %Object{guid: 7},
        unit: %Unit{level: 10, charmed_by: npc},
        player: %Player{},
        internal: %Internal{}
      }

      assert AttackTable.attacker_context(player).caster_owner_guid == npc
      assert CastContext.from_caster(player, %Spell{id: 1}, 10).caster_owner_guid == npc
    end

    test "a creator does not imply control" do
      guid = Guid.from_low_guid(:mob, 1, 1)
      mob = %Mob{object: %Object{guid: guid}, unit: %Unit{created_by: 7}}
      assert ControlOwner.guid(mob) == guid
    end
  end
end
