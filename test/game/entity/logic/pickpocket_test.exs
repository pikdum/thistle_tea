defmodule ThistleTea.Game.Entity.Logic.PickpocketTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Pickpocket
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastResolution
  alias ThistleTea.Game.Spell.CastResolution.Costs
  alias ThistleTea.Game.Spell.CastResolution.Followups
  alias ThistleTea.Game.Spell.CastResolution.PowerCost
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  setup [:caster_fixture]

  describe "validate/3" do
    test "requires stealth and a living nonfriendly creature with pockets", %{
      caster: caster,
      spell: spell,
      target: target
    } do
      assert :ok = Pickpocket.validate(caster, spell, target)

      assert {:error, :only_stealthed} =
               Pickpocket.validate(%{caster | unit: %{caster.unit | auras: []}}, spell, target)

      assert {:error, :target_no_pockets} = Pickpocket.validate(caster, spell, %{target | pickpocket_id: 0})
      assert {:error, :bad_targets} = Pickpocket.validate(caster, spell, %{target | friendly?: true})
      assert {:error, :bad_targets} = Pickpocket.validate(caster, spell, %{target | guid: 42})
      assert {:error, :bad_targets} = Pickpocket.validate(caster, spell, Map.put(target, :owner_guid, 42))
      assert {:error, :targets_dead} = Pickpocket.validate(caster, spell, %{target | alive?: false})
      assert {:error, :bad_targets} = Pickpocket.validate(caster, spell, nil)
      assert :ok = Pickpocket.validate(caster, %Spell{effects: []}, nil)
    end

    test "cast validation rejects pocketless targets before launching", %{caster: caster, spell: spell, target: target} do
      assert {:error, :target_no_pockets} =
               CastValidation.validate(caster, spell, Target.unit(target.guid), %{target | pickpocket_id: 0}, 0)
    end
  end

  describe "Casting.advance/2" do
    test "cast preparation preserves stealth but still interrupts invisibility", %{
      caster: caster,
      spell: spell,
      target: target
    } do
      invisibility = %Holder{
        spell: %Spell{id: 999, aura_interrupt_flags: 4},
        auras: [%AuraData{type: :mod_invisibility, amount: 100, misc_value: 0}]
      }

      caster = %{caster | unit: %{caster.unit | auras: caster.unit.auras ++ [invisibility]}}
      caster = Casting.start(caster, spell, Target.unit(target.guid), 1_000)
      assert Aura.has_aura?(caster, :mod_stealth)
      refute Aura.has_aura?(caster, :mod_invisibility)
    end

    test "a successful cast opens pockets while preserving stealth and peace", %{
      caster: caster,
      spell: spell,
      target: target
    } do
      caster = prepare(caster, spell, target.guid, :hit)
      assert {:finished, caster} = Casting.advance(caster, 1_000)
      assert Aura.has_aura?(caster, :mod_stealth)
      refute caster.internal.in_combat

      assert Enum.any?(
               caster.internal.events,
               &match?(%Effects.PickPocket{target_guid: guid} when guid == target.guid, &1)
             )

      refute Spell.starts_combat?(spell)
    end

    test "a resisted cast breaks stealth and enters combat without opening loot", %{
      caster: caster,
      spell: spell,
      target: target
    } do
      caster = prepare(caster, spell, target.guid, :resist)
      assert {:finished, caster} = Casting.advance(caster, 1_000)
      refute Aura.has_aura?(caster, :mod_stealth)
      assert caster.internal.in_combat
      refute Enum.any?(caster.internal.events, &is_struct(&1, Effects.PickPocket))
      assert Enum.any?(caster.internal.events, &match?(%Effects.DeliverSpellOutcome{outcome: :resist}, &1))
      assert Spell.starts_combat?(spell, :miss)
    end
  end

  defp prepare(caster, spell, guid, outcome) do
    hits = if outcome == :hit, do: [guid], else: []
    misses = if outcome == :hit, do: [], else: [%{guid: guid, reason: 2}]

    resolution = %CastResolution{
      hits: hits,
      misses: misses,
      impacts: [],
      costs: %Costs{
        power: %PowerCost{power_type: nil, amount: 0},
        channel_power: %PowerCost{power_type: nil, amount: 0},
        reagents: [],
        ammo: [],
        cast_item_guid: nil,
        modifier_holder_ids: []
      },
      followups: %Followups{
        packet_hits: hits,
        selected_unit_guid: guid,
        object_guid: nil,
        item_guid: nil,
        ground_position: nil,
        area_position: nil
      }
    }

    cast = %{Cast.new(spell, Target.unit(guid), 1_000) | phase: :launch, resolution: resolution}
    %{caster | internal: %{caster.internal | casting: cast}}
  end

  defp caster_fixture(_) do
    stealth = %Holder{
      spell: %Spell{id: 1784, aura_interrupt_flags: 15_367},
      caster_guid: 1,
      auras: [%AuraData{type: :mod_stealth, amount: 100}]
    }

    caster = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 60, auras: [stealth]},
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    spell = %Spell{
      id: 921,
      attributes: MapSet.new([:allow_while_stealthed, :threat_only_on_miss, :failure_breaks_stealth]),
      effects: [%Effect{index: 0, type: :pickpocket, implicit_target_a: :target_enemy}]
    }

    target = %{guid: Guid.from_low_guid(:mob, 299, 100), alive?: true, friendly?: false, pickpocket_id: 1}
    %{caster: caster, spell: spell, target: target}
  end
end
