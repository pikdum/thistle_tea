defmodule ThistleTea.Game.Entity.Logic.Aura.SingleTargetTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.SingleTargetClaim
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.SingleTarget
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:recipient]

  describe "apply_spell/5" do
    test "publishes only accepted limited applications", %{entity: entity, spell: spell} do
      {applied, events} = Aura.apply_spell(entity, 7, 60, spell, 100)
      assert [%Effects.SingleTargetAurasChanged{claims: [claim]}] = publications(events)
      assert claim.caster_guid == 7
      assert claim.target_guid == 8
      assert claim.generation == 1
      assert applied.internal.single_target_sequence == 1

      {ordinary, events} = Aura.apply_spell(entity, 7, 60, %{spell | custom_flags: 0}, 100)
      assert ordinary.internal.single_target_sequence == 0
      assert publications(events) == []

      immunity = %Spell{id: 20, effects: [%Effect{type: :apply_aura, aura: :mechanic_immunity, misc_value: 7}]}
      {immune, _events} = Aura.apply_spell(entity, 8, 60, immunity, 0)
      {blocked, events} = Aura.apply_spell(immune, 7, 60, %{spell | mechanic: 7}, 100)
      assert blocked.unit.auras == immune.unit.auras
      assert publications(events) == []
    end

    test "same-millisecond refresh advances generation and rejects stale removal", %{entity: entity, spell: spell} do
      {entity, events} = Aura.apply_spell(entity, 7, 60, spell, 100)
      [%Effects.SingleTargetAurasChanged{claims: [old]}] = publications(events)
      {refreshed, events} = Aura.apply_spell(entity, 7, 60, spell, 100)
      [%Effects.SingleTargetAurasChanged{claims: [current]}] = publications(events)
      assert current.generation == old.generation + 1
      assert {^refreshed, []} = SingleTarget.remove(refreshed, old, 100)

      {removed, events} = SingleTarget.remove(refreshed, current, 100)
      assert removed.unit.auras == []
      refute removed.internal.rooted?
      assert publications(events) == [%Effects.SingleTargetAurasChanged{claims: []}]
    end

    test "expiry, dispel, and death retire the claim through aura transitions", %{entity: entity, spell: spell} do
      spell = %{spell | dispel_type: 1}
      {entity, _events} = Aura.apply_spell(entity, 7, 60, spell, 100)
      {expired, events} = Aura.expire_due(entity, 1_100)
      assert expired.unit.auras == []
      assert publications(events) == [%Effects.SingleTargetAurasChanged{claims: []}]

      {dispelled, events} = Aura.dispel(entity, 1, 200)
      assert dispelled.unit.auras == []
      assert publications(events) == [%Effects.SingleTargetAurasChanged{claims: []}]

      dead = Core.take_damage(entity, 100, 200)
      assert dead.unit.auras == []
      assert publications(dead.internal.events) == [%Effects.SingleTargetAurasChanged{claims: []}]
      assert %Effects.SingleTargetCasterDied{} in dead.internal.events
    end

    test "unrelated transitions do not republish a claim", %{entity: entity, spell: spell} do
      {entity, _events} = Aura.apply_spell(entity, 7, 60, spell, 100)
      ordinary = %{spell | id: 11, custom_flags: 0, effects: [%Effect{type: :apply_aura, aura: :dummy}]}
      {_entity, events} = Aura.apply_spell(entity, 7, 60, ordinary, 200)
      assert publications(events) == []
    end
  end

  describe "conflicts?/2" do
    test "matches family and icon across ranks but isolates casters and recipients" do
      first = claim()
      second = %{first | target_guid: 9, holder_key: {12, 7, nil, nil}}
      assert SingleTarget.conflicts?(first, second)
      refute SingleTarget.conflicts?(first, %{second | caster_guid: 10})
      refute SingleTarget.conflicts?(first, %{second | target_guid: 8})
      refute SingleTarget.conflicts?(first, %{second | spell_family: 9})
      refute SingleTarget.conflicts?(first, %{second | spell_icon: 2})
    end

    test "polymorph forms and different judgements share their respective limits" do
      for category <- [:mage_polymorph, :paladin_judgement] do
        first = %{claim() | category: category}
        assert SingleTarget.conflicts?(first, %{first | target_guid: 9, spell_icon: 999})
      end

      first = %{claim() | category: :warlock_curse}
      refute SingleTarget.conflicts?(first, %{first | target_guid: 9, spell_icon: 999})
    end
  end

  describe "detach/2" do
    test "removes foreign limited auras while retaining ordinary and self-owned auras", %{entity: entity, spell: spell} do
      {entity, _events} = Aura.apply_spell(entity, 7, 60, spell, 100)
      {entity, _events} = Aura.apply_spell(entity, 8, 60, %{spell | id: 12}, 100)
      {entity, _events} = Aura.apply_spell(entity, 7, 60, %{spell | id: 13, custom_flags: 0}, 100)
      entity = SingleTarget.detach(entity, 200)
      assert Enum.map(entity.unit.auras, & &1.spell.id) == [12, 13]
      assert %Effects.SingleTargetAurasLeft{} in entity.internal.events

      assert [%Effects.SingleTargetAurasChanged{claims: [claim]} | _] =
               Enum.reverse(publications(entity.internal.events))

      assert claim.caster_guid == 8
    end

    test "respawn removes self-owned claims without reusing generations", %{entity: entity, spell: spell} do
      {entity, events} = Aura.apply_spell(entity, 8, 60, spell, 100)
      [%Effects.SingleTargetAurasChanged{claims: [old]}] = publications(events)
      cleared = SingleTarget.detach(entity, 100, keep_self?: false)
      assert cleared.unit.auras == []
      {reapplied, events} = Aura.apply_spell(cleared, 8, 60, spell, 100)
      [%Effects.SingleTargetAurasChanged{claims: [current]}] = publications(events)
      assert current.generation > old.generation
      assert {^reapplied, []} = SingleTarget.remove(reapplied, old, 100)
    end
  end

  describe "handle_cast/2" do
    test "mob and player owners remove only the requested generation", %{entity: entity, spell: spell} do
      {entity, events} = Aura.apply_spell(entity, 7, 60, spell, 100)
      [%Effects.SingleTargetAurasChanged{claims: [claim]}] = publications(events)
      request = {:remove_single_target_aura, claim, :removed}
      assert {:noreply, mob, _continue} = MobServer.handle_cast(request, entity)
      assert mob.unit.auras == []

      character = %Character{
        object: entity.object,
        unit: entity.unit,
        internal: entity.internal,
        movement_block: entity.movement_block
      }

      assert {:noreply, state, _continue} = PlayerServer.handle_cast(request, %State{character: character})
      assert state.character.unit.auras == []
    end
  end

  defp publications(events), do: Enum.filter(events, &is_struct(&1, Effects.SingleTargetAurasChanged))

  defp claim do
    %SingleTargetClaim{
      caster_guid: 7,
      target_guid: 8,
      holder_key: {10, 7, nil, nil},
      generation: 1,
      spell_family: 3,
      spell_icon: 82
    }
  end

  defp recipient(_context) do
    %{
      entity: %Mob{
        object: %Object{guid: 8},
        unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      },
      spell: %Spell{
        id: 10,
        custom_flags: 256,
        spell_family: 3,
        spell_icon: 82,
        duration_ms: 1_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_root, base_points: 0}]
      }
    }
  end
end
