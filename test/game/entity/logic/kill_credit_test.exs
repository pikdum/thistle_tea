defmodule ThistleTea.Game.Entity.Logic.KillCreditTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura.ControlSync
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.KillCredit
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell

  describe "eligible?/1" do
    test "retains the lethal controller after death releases charm and clears it on respawn" do
      for type <- [:mod_charm, :mod_possess] do
        holder = %Holder{spell: %Spell{id: 1}, caster_guid: 7, auras: [%Aura{type: type}]}

        mob = %Mob{
          object: %Object{guid: Guid.runtime(:mob, 1)},
          unit: %Unit{health: 100, max_health: 100, level: 24, faction_template: 14, auras: [holder]},
          movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
          internal: %Internal{creature: %Creature{}}
        }

        {controlled, _} = ControlSync.sync(mob, 0)
        refute KillCredit.eligible?(controlled)
        {dead, _} = Core.take_damage_with_absorb(controlled, 100, 1_000, source: 8)
        assert dead.unit.health == 0
        assert dead.internal.pet == nil
        assert dead.unit.charmed_by == 0
        refute KillCredit.eligible?(dead)
        assert KillCredit.eligible?(Mob.respawn(dead))
      end
    end

    test "rewards NPC companions while excluding every player control form" do
      mob = %Mob{object: %Object{guid: Guid.runtime(:pet, 1)}, internal: %Internal{}}
      npc = Guid.runtime(:mob, 2)

      for kind <- [:hunter, :summon, :guardian, :creature_pet, :mini_pet, :possessed, :charmed] do
        owned = %{mob | internal: %{mob.internal | pet: %Pet{kind: kind, owner_guid: npc}}}
        assert KillCredit.eligible?(owned)
        refute KillCredit.eligible?(%{owned | internal: %{owned.internal | pet: %{owned.internal.pet | owner_guid: 7}}})
        refute KillCredit.eligible?(%{owned | unit: %{owned.unit | charmed_by: 7}})
      end
    end
  end
end
