defmodule ThistleTea.Game.Entity.Logic.CreatureImmunityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CreatureImmunity
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:creature]

  describe "receive/4" do
    test "a protected spell mechanic rejects damage and control together", %{entity: entity, spell: spell} do
      {unchanged, events} = SpellEffect.receive(entity, 2, %{spell | mechanic: 12}, 1_000)
      assert unchanged.unit.health == 100
      refute Aura.has_aura?(unchanged, :mod_stun)
      assert [%Effects.SpellLogMiss{reason: :immune}] = events
    end

    test "an effect mechanic rejects only that effect", %{entity: entity, spell: spell} do
      {damaged, events} = SpellEffect.receive(entity, 2, spell, 1_000)
      assert damaged.unit.health == 90
      refute Aura.has_aura?(damaged, :mod_stun)
      assert Enum.any?(events, &match?(%Effects.SpellDamage{}, &1))
    end

    test "self casts and restriction-ignoring spells bypass template protection", %{entity: entity, spell: spell} do
      for {caster, attributes} <- [{1, MapSet.new()}, {2, MapSet.new([:ignore_caster_and_target_restrictions])}] do
        {updated, _events} = SpellEffect.receive(entity, caster, %{spell | attributes: attributes}, 1_000)
        assert Aura.has_aura?(updated, :mod_stun)
      end
    end

    test "direct aura application retains the same effect protection", %{entity: entity, spell: spell} do
      {updated, _events} = Aura.apply_spell(entity, 2, 10, spell, 1_000)
      refute Aura.has_aura?(updated, :mod_stun)
    end
  end

  describe "spell?/3" do
    test "no-immunities bypasses the spell mechanic but not effect mechanics", %{entity: entity, spell: spell} do
      context = %CastContext{caster_guid: 2}
      spell = %{spell | mechanic: 12, attributes: MapSet.new([:no_immunities])}
      refute CreatureImmunity.spell?(entity, context, spell)
      assert CreatureImmunity.effect?(entity, context, spell, List.last(spell.effects))
      refute CreatureImmunity.mechanic?(entity, 0)
      refute CreatureImmunity.mechanic?(entity, 32)
    end
  end

  defp creature(_context) do
    entity = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 10},
      internal: %Internal{creature: %Creature{mechanic_immune_mask: 2048}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    spell = %Spell{
      id: 99,
      school: :physical,
      duration_ms: 5_000,
      effects: [
        %Effect{index: 0, type: :school_damage, base_points: 10},
        %Effect{index: 1, type: :apply_aura, aura: :mod_stun, mechanic: 12}
      ]
    }

    %{entity: entity, spell: spell}
  end
end
