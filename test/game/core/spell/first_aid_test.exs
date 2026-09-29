defmodule ThistleTea.Game.Core.Spell.FirstAidTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.CastValidation
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef

  setup [:characters]

  describe "receive/4" do
    test "queues the recipient's lockout with original caster and item attribution", context do
      {target, events} = SpellEffect.receive(context.target, context.cast, bandage(), 1000)
      assert Aura.has_spell?(target, 18_610)

      assert %Effects.TriggerSpell{
               source_guid: 1,
               target_guid: 2,
               spell_id: 11_196,
               cast_item_guid: 500,
               hit_context: hit
             } =
               Enum.find(events, &is_struct(&1, Effects.TriggerSpell))

      assert hit.cast_item_guid == 500
      assert target.unit.health == 100
    end

    test "lockout leaves the current channel healing and survives its completion", context do
      target = start_bandage(context)
      {target, _events} = Aura.tick(target, 2000)
      assert target.unit.health == 350

      target = Enum.reduce(3000..9000//1000, target, fn now, target -> elem(Aura.tick(target, now), 0) end)
      assert target.unit.health == 2100
      refute Aura.has_spell?(target, 18_610)
      assert Aura.has_spell?(target, 11_196)
      assert Aura.friendly_mechanics(target) == MapSet.new([16])
    end

    test "damage interrupts healing without clearing the lockout", context do
      target = start_bandage(context)
      target = Entity.take_damage(target, 1, 1500)
      {target, _events} = Aura.tick(target, 2000)
      assert target.unit.health == 99
      refute Aura.has_spell?(target, 18_610)
      assert Aura.has_spell?(target, 11_196)
    end

    test "an immune hit cannot start healing or refresh the existing lockout", context do
      {target, _events} = SpellEffect.receive(context.target, context.cast, lockout(), 1000)
      [holder] = target.unit.auras
      {target, events} = SpellEffect.receive(target, context.cast, bandage(), 2000)
      assert target.unit.auras == [holder]
      assert [%Effects.SpellLogMiss{reason: :immune}] = events
    end
  end

  describe "validate/6" do
    test "rejects self and other casters until the recipient's lockout expires", context do
      target = start_bandage(context)

      assert {:error, :target_aurastate} =
               CastValidation.validate(target, bandage(), Target.unit(2), :self, 2000)

      assert {:error, :target_aurastate} = validate_other(context.caster, target, 2000)
      {target, _events} = Aura.expire_due(target, 61_000)
      assert Aura.friendly_mechanics(target) == MapSet.new()
      assert :ok = validate_other(context.caster, target, 61_000)
    end

    test "the caster's lockout does not prevent bandaging somebody else", context do
      {caster, _events} = SpellEffect.receive(context.caster, 1, lockout(), 1000)
      assert :ok = validate_other(caster, context.target, 2000)
    end
  end

  defp validate_other(caster, target, now) do
    info = %{
      guid: target.object.guid,
      alive?: true,
      friendly?: true,
      hostile?: false,
      friendly_mechanic_immunities: Aura.friendly_mechanics(target),
      position: {WorldRef.open(0), 1.0, 0.0, 0.0}
    }

    CastValidation.validate(caster, bandage(), Target.unit(target.object.guid), info, now)
  end

  defp start_bandage(context) do
    {target, _events} = SpellEffect.receive(context.target, context.cast, bandage(), 1000)
    {target, _events} = SpellEffect.receive(target, context.cast, lockout(), 1000)
    target
  end

  defp characters(_context) do
    caster = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 3000, level: 60, auras: []},
      player: %Player{},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{
      caster: caster,
      target: %{caster | object: %Object{guid: 2}},
      cast: %CastContext{caster_guid: 1, caster_level: 60, target_guid: 2, target_role: :other, cast_item_guid: 500}
    }
  end

  defp bandage do
    %Spell{
      id: 18_610,
      script_name: "spell_first_aid",
      mechanic: 16,
      duration_ms: 8000,
      range_yards: 15.0,
      attributes: MapSet.new([:channeled]),
      aura_interrupt_flags: 2,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: :periodic_heal,
          amplitude_ms: 1000,
          base_points: 250,
          implicit_target_a: :target_ally
        }
      ]
    }
  end

  defp lockout do
    %Spell{
      id: 11_196,
      duration_ms: 60_000,
      attributes: MapSet.new([:negative]),
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mechanic_immunity, misc_value: 16}]
    }
  end
end
