defmodule ThistleTea.Game.Spell.CastValidationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Area
  alias ThistleTea.Game.Spell.Area.Context, as: AreaContext
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  @now 10_000

  describe "validate/6 reactive windows" do
    test "Counterattack requires a current parry against the selected target" do
      npc = caster(class: 3)
      hunter = %Character{object: npc.object, unit: npc.unit, player: %Player{}, internal: npc.internal}
      spell = harmful_spell(caster_aura_state: 7, script_name: "spell_hunter_counterattack")

      assert {:error, :cant_do_that_yet} =
               CastValidation.validate(hunter, spell, Target.unit(7), hostile_target(), @now)

      hunter = Reactive.mark_defense(hunter, 7, :parry, @now)
      assert :ok = CastValidation.validate(hunter, spell, Target.unit(7), hostile_target(), @now + 1)

      assert {:error, :bad_targets} =
               CastValidation.validate(hunter, spell, Target.unit(8), hostile_target(guid: 8), @now + 1)

      assert {:error, :cant_do_that_yet} =
               CastValidation.validate(hunter, spell, Target.unit(7), hostile_target(), @now + 4_000)
    end

    test "Riposte remains unavailable after a dodge and becomes usable after a parry" do
      npc = caster(class: 4)
      rogue = %Character{object: npc.object, unit: npc.unit, player: %Player{}, internal: npc.internal}
      spell = harmful_spell(caster_aura_state: 1)
      rogue = Reactive.mark_defense(rogue, 7, :dodge, @now)

      assert {:error, :cant_do_that_yet} =
               CastValidation.validate(rogue, spell, Target.unit(7), hostile_target(), @now + 1)

      rogue = Reactive.mark_defense(rogue, 7, :parry, @now + 100)
      assert :ok = CastValidation.validate(rogue, spell, Target.unit(7), hostile_target(), @now + 101)
    end
  end

  describe "validate/6 terrain requirements" do
    test "restricts players with known terrain and leaves creatures and unknown terrain unaffected" do
      npc = caster()
      player = %Character{object: npc.object, unit: npc.unit, internal: npc.internal}

      for {attribute, forbidden} <- [only_outdoors: false, only_indoors: true] do
        spell = helpful_spell(attributes: MapSet.new([attribute]))

        assert CastValidation.validate(player, spell, Target.none(), nil, @now, outdoors?: forbidden) ==
                 {:error, attribute}

        for outdoors <- [not forbidden, nil] do
          assert CastValidation.validate(player, spell, Target.none(), nil, @now, outdoors?: outdoors) == :ok
        end

        assert CastValidation.validate(npc, spell, Target.none(), nil, @now, outdoors?: forbidden) == :ok
      end
    end
  end

  describe "validate/6 creature resources" do
    test "ordinary creatures can use non-mana abilities without those power pools" do
      for type <- 1..4 do
        spell = helpful_spell(mana_cost: 60, power_type: type)
        assert :ok = CastValidation.validate(caster(), spell, Target.none(), nil, @now)
      end
    end

    test "creatures without base mana can cast mana abilities" do
      npc = caster(power1: 0, max_power1: 0, base_mana: 0)
      assert :ok = CastValidation.validate(npc, helpful_spell(mana_cost: 60, power_type: 0), Target.none(), nil, @now)
    end

    test "mana-using creatures still need enough current mana" do
      for max_mana <- [0, 100] do
        npc = caster(power1: 0, max_power1: max_mana, base_mana: 100)

        assert {:error, :no_power} =
                 CastValidation.validate(npc, helpful_spell(mana_cost: 60, power_type: 0), Target.none(), nil, @now)
      end
    end

    test "pets and players still require every requested power type" do
      npc = caster(power1: 0, max_power1: 0, base_mana: 0)
      pet = %{npc | internal: %{npc.internal | pet: %Pet{owner_guid: 1}}}
      player = %Character{object: npc.object, unit: npc.unit, internal: npc.internal}

      for source <- [pet, player], type <- 0..4 do
        spell = helpful_spell(mana_cost: 60, power_type: type)
        assert {:error, :no_power} = CastValidation.validate(source, spell, Target.none(), nil, @now)
      end
    end

    test "creatures require health strictly above a health cost" do
      npc = caster(health: 60, power1: 0, max_power1: 0, base_mana: 0)
      spell = helpful_spell(mana_cost: 60, power_type: -2)
      assert {:error, :no_power} = CastValidation.validate(npc, spell, Target.none(), nil, @now)
    end

    test "weapon item restrictions apply to player inventories" do
      npc = caster()
      player = %Character{object: npc.object, unit: npc.unit, internal: npc.internal}
      spell = helpful_spell(mana_cost: 0, equipped_item_class: 2, equipped_item_subclass_mask: 0x8000)
      assert :ok = CastValidation.validate(npc, spell, Target.none(), nil, @now)

      assert {:error, :equipped_item_class} =
               CastValidation.validate(player, spell, Target.none(), nil, @now)

      assert :ok =
               CastValidation.validate(player, spell, Target.none(), nil, @now,
                 equipped_items: [%{class: 2, subclass: 15}]
               )
    end
  end

  describe "validate/6 spell areas" do
    test "rejects an out-of-area cast before spending power" do
      source = caster()
      spell = harmful_spell(area_rules: [%Area{area_id: 139}])

      assert CastValidation.validate(source, spell, Target.unit(7), hostile_target(), @now,
               spell_area: %AreaContext{zone_id: 148}
             ) == {:error, :requires_area}

      assert CastValidation.validate(source, spell, Target.unit(7), hostile_target(), @now,
               spell_area: %AreaContext{zone_id: 139}
             ) == :ok

      assert source.unit.power1 == 100
    end
  end

  describe "validate/6 target flags" do
    test "NPC and player-controlled casters use different immunity flags" do
      spell = %Spell{id: 5, effects: [%Effect{type: :instakill, implicit_target_a: :any_unit}]}
      npc = caster()
      npc = %{npc | object: %{npc.object | guid: Guid.from_low_guid(:mob, 1, 1)}}
      pet = %{npc | internal: %{npc.internal | pet: %Pet{owner_guid: 100}}}

      for {source, immune, allowed} <- [{npc, 0x200, 0x100}, {pet, 0x100, 0x200}] do
        assert {:error, :bad_targets} =
                 CastValidation.validate(source, spell, Target.unit(7), hostile_target(unit_flags: immune), @now)

        assert :ok = CastValidation.validate(source, spell, Target.unit(7), hostile_target(unit_flags: allowed), @now)
      end
    end

    test "any-unit instant kills respect player immunity and targetability" do
      spell = %Spell{id: 5, effects: [%Effect{type: :instakill, implicit_target_a: :any_unit}]}

      for flags <- [0x100, 0x2, 0x10000, 0x02000000] do
        target = hostile_target(unit_flags: flags)
        assert {:error, :bad_targets} = CastValidation.validate(caster(), spell, Target.unit(7), target, @now)
      end

      assert :ok = CastValidation.validate(caster(), spell, Target.unit(7), friendly_target(unit_flags: 0), @now)
    end

    test "any-unit healing respects player immunity without inheriting harmful-only flags" do
      spell = %Spell{id: 99, effects: [%Effect{type: :heal, implicit_target_a: :any_unit}]}

      for flags <- [0x100, 0x10000] do
        assert {:error, :bad_targets} =
                 CastValidation.validate(caster(), spell, Target.unit(7), friendly_target(unit_flags: flags), @now)
      end

      assert :ok =
               CastValidation.validate(caster(), spell, Target.unit(7), friendly_target(unit_flags: 0x02000200), @now)
    end
  end

  defp caster(unit_overrides \\ []) do
    unit =
      struct!(
        %Unit{health: 100, max_health: 100, power1: 100, max_power1: 100, auras: []},
        unit_overrides
      )

    %Mob{
      object: %Object{guid: 100},
      unit: unit,
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: %WorldRef{map_id: 0}}
    }
  end

  defp harmful_spell(overrides \\ []) do
    struct!(
      %Spell{
        id: 133,
        mana_cost: 30,
        power_type: 0,
        range_yards: 35.0,
        effects: [%Effect{type: :school_damage, implicit_target_a: :target_enemy}]
      },
      overrides
    )
  end

  defp helpful_spell(overrides \\ []) do
    struct!(
      %Spell{
        id: 1454,
        mana_cost: 0,
        range_yards: 40.0,
        effects: [%Effect{type: :heal, implicit_target_a: :target_ally}]
      },
      overrides
    )
  end

  defp hostile_target(overrides \\ []) do
    Map.merge(
      %{
        guid: 7,
        alive?: true,
        hostile?: true,
        friendly?: false,
        attackable?: true,
        position: {WorldRef.open(0), 10.0, 0.0, 0.0}
      },
      Map.new(overrides)
    )
  end

  defp friendly_target(overrides \\ []) do
    hostile_target([hostile?: false, friendly?: true, attackable?: false] ++ overrides)
  end

  defp control_holder(type) do
    %Holder{
      spell: %Spell{id: 5_000},
      caster_guid: 9,
      auras: [%AuraData{index: 0, type: type}]
    }
  end

  describe "caster state gating" do
    test "rejects a concealed explicit target" do
      assert {:error, :bad_targets} =
               CastValidation.validate(
                 caster(),
                 harmful_spell(),
                 Target.self(100),
                 hostile_target(visible?: false),
                 @now
               )
    end

    test "stunned casters cannot cast, except stun-immunity-purging spells" do
      stunned = caster(auras: [control_holder(:mod_stun)])

      assert {:error, :stunned} =
               CastValidation.validate(stunned, harmful_spell(), Target.unit(7), hostile_target(), @now)

      blink =
        helpful_spell(
          attributes: MapSet.new([:immunity_purges_effect]),
          effects: [%Effect{type: :apply_aura, aura: :mechanic_immunity, misc_value: 12, implicit_target_a: :caster}]
        )

      assert :ok = CastValidation.validate(stunned, blink, Target.none(), nil, @now)
    end

    test "state-immunity purges allow casting through matching control only" do
      for {type, error} <- [{:mod_stun, :stunned}, {:mod_fear, :fleeing}, {:mod_confuse, :confused}] do
        controlled = caster(auras: [control_holder(type)])

        spell =
          helpful_spell(
            attributes: MapSet.new([:immunity_purges_effect]),
            effects: [%Effect{type: :apply_aura, aura: :state_immunity, misc_value: type, implicit_target_a: :caster}]
          )

        assert :ok = CastValidation.validate(controlled, spell, Target.none(), nil, @now)

        assert {:error, ^error} =
                 CastValidation.validate(controlled, %{spell | attributes: MapSet.new()}, Target.none(), nil, @now)
      end
    end

    test "fear and confusion prevent casting" do
      feared = caster(auras: [control_holder(:mod_fear)])
      confused = caster(auras: [control_holder(:mod_confuse)])

      assert {:error, :fleeing} =
               CastValidation.validate(feared, harmful_spell(), Target.unit(7), hostile_target(), @now)

      assert {:error, :confused} =
               CastValidation.validate(confused, harmful_spell(), Target.unit(7), hostile_target(), @now)
    end

    test "fear suppressed by recklessness permits casting" do
      suppressed = caster(auras: [control_holder(:mod_fear), control_holder(:prevent_fleeing)])
      assert :ok = CastValidation.validate(suppressed, harmful_spell(), Target.unit(7), hostile_target(), @now)
    end

    test "silence blocks magic but not physical abilities" do
      silenced = caster(auras: [control_holder(:mod_silence)])

      assert {:error, :silenced} =
               CastValidation.validate(
                 silenced,
                 harmful_spell(prevention_type: 1),
                 Target.unit(7),
                 hostile_target(),
                 @now
               )

      assert :ok =
               CastValidation.validate(
                 silenced,
                 harmful_spell(prevention_type: 0),
                 Target.unit(7),
                 hostile_target(),
                 @now
               )
    end

    test "pacify blocks physical-prevention abilities only" do
      pacified = caster(auras: [control_holder(:mod_pacify)])

      assert {:error, :pacified} =
               CastValidation.validate(
                 pacified,
                 harmful_spell(prevention_type: 2),
                 Target.unit(7),
                 hostile_target(),
                 @now
               )

      assert :ok =
               CastValidation.validate(
                 pacified,
                 harmful_spell(prevention_type: 1),
                 Target.unit(7),
                 hostile_target(),
                 @now
               )
    end

    test "an interrupt school lockout blocks same-school casts until it expires" do
      locked = Cooldowns.lock_schools(caster(), Spell.school_mask(:fire), 5_000, @now)
      fire = harmful_spell(school: :fire, prevention_type: 1)
      frost = harmful_spell(id: 116, school: :frost, prevention_type: 1)

      assert {:error, :silenced} = CastValidation.validate(locked, fire, Target.unit(7), hostile_target(), @now)
      assert :ok = CastValidation.validate(locked, frost, Target.unit(7), hostile_target(), @now)
      assert :ok = CastValidation.validate(locked, fire, Target.unit(7), hostile_target(), @now + 5_001)
    end
  end

  describe "minimum range and global cooldown" do
    test "casts inside the minimum range fail as too close" do
      charge = harmful_spell(min_range_yards: 8.0, range_yards: 25.0)

      assert {:error, :too_close} =
               CastValidation.validate(
                 caster(),
                 charge,
                 Target.unit(7),
                 hostile_target(position: {WorldRef.open(0), 3.0, 0.0, 0.0}),
                 @now
               )

      assert :ok = CastValidation.validate(caster(), charge, Target.unit(7), hostile_target(), @now)
    end

    test "the global cooldown blocks new casts until it lapses" do
      spell = harmful_spell(gcd_ms: 1_500, gcd_category: 133)
      on_gcd = Cooldowns.trigger_gcd(caster(), spell, @now)

      assert {:error, :not_ready} =
               CastValidation.validate(on_gcd, spell, Target.unit(7), hostile_target(), @now + 100)

      assert :ok = CastValidation.validate(on_gcd, spell, Target.unit(7), hostile_target(), @now + 1_500)

      gcd_free = harmful_spell(id: 2764, gcd_ms: 0)

      assert :ok = CastValidation.validate(on_gcd, gcd_free, Target.unit(7), hostile_target(), @now + 100)
    end
  end

  describe "channel_in_range?/3" do
    test "uses combat reach and the VMangos hostile channel grace range" do
      spell = harmful_spell(range_yards: 30.0, attributes: MapSet.new([:channeled]))
      caster = caster(combat_reach: 1.5)

      inside_grace = hostile_target(position: {WorldRef.open(0), 53.0, 0.0, 0.0}, combat_reach: 12.5)
      outside_grace = hostile_target(position: {WorldRef.open(0), 54.0, 0.0, 0.0}, combat_reach: 12.5)

      assert CastValidation.channel_in_range?(caster, spell, inside_grace)
      refute CastValidation.channel_in_range?(caster, spell, outside_grace)
    end

    test "allows an established channel when target position is unavailable" do
      assert CastValidation.channel_in_range?(caster(), harmful_spell(), hostile_target(position: nil))
    end
  end

  describe "stance gating" do
    test "stance-locked abilities fail outside their form, including no form at all" do
      claw = harmful_spell(id: 1082, stances: 0x1)

      assert {:error, :only_shapeshift} =
               CastValidation.validate(caster(), claw, Target.unit(7), hostile_target(), @now)

      assert {:error, :only_shapeshift} =
               CastValidation.validate(caster(shapeshift_form: 5), claw, Target.unit(7), hostile_target(), @now)

      assert :ok = CastValidation.validate(caster(shapeshift_form: 1), claw, Target.unit(7), hostile_target(), @now)
    end

    test "normal spells fail in true forms but cast fine in warrior-style stances" do
      fireball = harmful_spell(attributes: MapSet.new([:not_while_shapeshifted]))

      assert {:error, :not_shapeshift} =
               CastValidation.validate(caster(shapeshift_form: 1), fireball, Target.unit(7), hostile_target(), @now)

      assert :ok =
               CastValidation.validate(caster(shapeshift_form: 17), fireball, Target.unit(7), hostile_target(), @now)

      assert :ok = CastValidation.validate(caster(), fireball, Target.unit(7), hostile_target(), @now)
    end

    test "stance-excluded spells fail in the excluded form" do
      renew = helpful_spell(stances_not: 0x08000000)

      assert {:error, :not_shapeshift} =
               CastValidation.validate(caster(shapeshift_form: 28), renew, Target.none(), nil, @now)

      assert :ok = CastValidation.validate(caster(), renew, Target.none(), nil, @now)
    end
  end

  describe "validate/6" do
    test "queues next-swing melee attacks beyond combat range" do
      spell = harmful_spell(range_yards: 5.0, melee_range?: true, attributes: MapSet.new([:on_next_swing]))
      target = hostile_target(position: {WorldRef.open(0), 100.0, 0.0, 0.0})
      assert :ok = CastValidation.validate(caster(), spell, Target.unit(7), target, @now)

      assert {:error, :out_of_range} =
               CastValidation.validate(caster(), %{spell | melee_range?: false}, Target.unit(7), target, @now)

      assert {:error, :out_of_range} =
               CastValidation.validate(caster(), %{spell | attributes: MapSet.new()}, Target.unit(7), target, @now)

      other_world = %{target | position: {WorldRef.instance(0, 1), 1.0, 0.0, 0.0}}
      assert {:error, :out_of_range} = CastValidation.validate(caster(), spell, Target.unit(7), other_world, @now)

      assert {:error, :targets_dead} =
               CastValidation.validate(caster(), spell, Target.unit(7), %{target | alive?: false}, @now)

      assert {:error, :no_power} = CastValidation.validate(caster(power1: 0), spell, Target.unit(7), target, @now)
    end

    test "passes a valid hostile cast" do
      assert :ok =
               CastValidation.validate(caster(), harmful_spell(), Target.unit(7), hostile_target(), @now)
    end

    test "uses current health for health-powered spells" do
      spell = helpful_spell(mana_cost: 30, power_type: -2)

      assert :ok = CastValidation.validate(caster(health: 31), spell, Target.none(), nil, @now)
      assert {:error, :no_power} = CastValidation.validate(caster(health: 30), spell, Target.none(), nil, @now)
    end

    test "restricts Exorcism and Holy Wrath to undead or demons" do
      exorcism = harmful_spell(name: "Exorcism", target_creature_type_mask: 36)
      holy_wrath = harmful_spell(name: "Holy Wrath", target_creature_type_mask: 36)

      assert :ok =
               CastValidation.validate(caster(), exorcism, Target.unit(7), hostile_target(creature_type: 6), @now)

      assert :ok =
               CastValidation.validate(caster(), holy_wrath, Target.unit(7), hostile_target(creature_type: 3), @now)

      assert {:error, :bad_targets} =
               CastValidation.validate(caster(), exorcism, Target.unit(7), hostile_target(creature_type: 7), @now)

      holy_wrath = %{
        holy_wrath
        | effects: [%Effect{type: :school_damage, implicit_target_a: :aoe_enemy_at_caster}]
      }

      assert :ok = CastValidation.validate(caster(), holy_wrath, Target.none(), nil, @now)
    end

    test "restricts Turn Undead to undead targets" do
      turn_undead = %{
        harmful_spell(name: "Turn Undead", target_creature_type_mask: 32)
        | effects: [%Effect{type: :apply_aura, aura: :mod_fear, implicit_target_a: :target_enemy}]
      }

      assert :ok =
               CastValidation.validate(caster(), turn_undead, Target.unit(7), hostile_target(creature_type: 6), @now)

      assert {:error, :bad_targets} =
               CastValidation.validate(caster(), turn_undead, Target.unit(7), hostile_target(creature_type: 3), @now)
    end

    test "dismiss pet ignores the DBC creature-type mask" do
      dismiss_pet = %Spell{
        id: 2641,
        target_creature_type_mask: 1,
        effects: [
          %Effect{type: :power_drain, misc_value: 4, implicit_target_a: :pet},
          %Effect{type: :dismiss_pet, implicit_target_a: :pet}
        ]
      }

      target_info =
        friendly_target()
        |> Map.delete(:creature_type)
        |> Map.put(:power_type, 2)

      assert :ok = CastValidation.validate(caster(), dismiss_pet, Target.none(), target_info, @now)

      assert {:error, :bad_targets} =
               CastValidation.validate(caster(), %{dismiss_pet | id: 999}, Target.unit(7), target_info, @now)
    end

    test "rejects a dead caster" do
      assert {:error, :caster_dead} =
               CastValidation.validate(caster(health: 0), harmful_spell(), Target.unit(7), hostile_target(), @now)
    end

    test "allows only healing spells in Spirit of Redemption" do
      spirit = %Holder{spell: %Spell{id: 27_827}}
      caster = caster(auras: [spirit])

      renew =
        helpful_spell(effects: [%Effect{type: :apply_aura, aura: :periodic_heal, implicit_target_a: :target_ally}])

      shield =
        helpful_spell(effects: [%Effect{type: :apply_aura, aura: :school_absorb, implicit_target_a: :target_ally}])

      assert :ok = CastValidation.validate(caster, renew, Target.unit(7), friendly_target(), @now)

      assert {:error, :not_shapeshift} =
               CastValidation.validate(caster, shield, Target.unit(7), friendly_target(), @now)

      assert {:error, :not_shapeshift} =
               CastValidation.validate(caster, harmful_spell(), Target.unit(7), hostile_target(), @now)
    end

    test "rejects insufficient power" do
      assert {:error, :no_power} =
               CastValidation.validate(caster(power1: 10), harmful_spell(), Target.unit(7), hostile_target(), @now)
    end

    test "rejects a spell still on cooldown and allows it after expiry" do
      spell = harmful_spell(recovery_time_ms: 8_000)
      caster = Cooldowns.start(caster(), spell, @now)

      assert {:error, :not_ready} =
               CastValidation.validate(caster, spell, Target.unit(7), hostile_target(), @now + 7_999)

      assert :ok =
               CastValidation.validate(caster, spell, Target.unit(7), hostile_target(), @now + 8_000)
    end

    test "deferred spells reject cooldowns without disturbing the client's disabled state" do
      spell = harmful_spell(recovery_time_ms: 8_000, gcd_ms: 1_500, attributes: MapSet.new([:cooldown_on_event]))
      pending = Cooldowns.start(caster(), spell, @now)
      {active, [_]} = Cooldowns.activate(pending, spell.id, @now + 1_000)
      on_gcd = Cooldowns.trigger_gcd(caster(), spell, @now)

      for blocked <- [pending, active, on_gcd] do
        assert {:error, :dont_report} =
                 CastValidation.validate(blocked, spell, Target.unit(7), hostile_target(), @now + 1_001)
      end

      assert :ok = CastValidation.validate(active, spell, Target.unit(7), hostile_target(), @now + 9_000)
    end

    test "rejects missing reagents and passes when they are on hand" do
      spell = helpful_spell(reagents: [{17_056, 1}])

      assert {:error, :reagents} =
               CastValidation.validate(caster(), spell, Target.unit(100), :self, @now, count_item: fn _ -> 0 end)

      assert :ok =
               CastValidation.validate(caster(), spell, Target.unit(100), :self, @now, count_item: fn _ -> 2 end)
    end

    test "rejects a friendly target for a harmful spell" do
      assert {:error, :target_friendly} =
               CastValidation.validate(caster(), harmful_spell(), Target.unit(7), friendly_target(), @now)
    end

    test "rejects a dead target for a harmful spell" do
      assert {:error, :targets_dead} =
               CastValidation.validate(caster(), harmful_spell(), Target.unit(7), hostile_target(alive?: false), @now)
    end

    test "rejects an unattackable neutral target for a harmful spell" do
      target = hostile_target(hostile?: false, attackable?: false)

      assert {:error, :bad_targets} =
               CastValidation.validate(caster(), harmful_spell(), Target.unit(7), target, @now)
    end

    test "rejects a hostile target for a helpful spell" do
      assert {:error, :target_enemy} =
               CastValidation.validate(caster(), helpful_spell(), Target.unit(7), hostile_target(), @now)
    end

    test "allows a self-targeting spell cast with an enemy selected" do
      arcane_missiles = %Spell{
        id: 5143,
        mana_cost: 50,
        power_type: 0,
        range_yards: 30.0,
        attributes: MapSet.new([:channeled]),
        effects: [%Effect{type: :apply_aura, aura: :periodic_trigger_spell, implicit_target_a: :caster}]
      }

      assert :ok =
               CastValidation.validate(caster(), arcane_missiles, Target.unit(7), hostile_target(), @now)

      assert {:error, :targets_dead} =
               CastValidation.validate(
                 caster(),
                 arcane_missiles,
                 Target.unit(7),
                 hostile_target(alive?: false),
                 @now
               )
    end

    test "requires a unit target for harmful spells" do
      assert {:error, :bad_implicit_targets} =
               CastValidation.validate(caster(), harmful_spell(), Target.none(), nil, @now)

      assert {:error, :bad_targets} =
               CastValidation.validate(caster(), harmful_spell(), Target.unit(100), :self, @now)

      assert {:error, :bad_targets} =
               CastValidation.validate(caster(), harmful_spell(), Target.unit(7), :unknown, @now)
    end

    test "rejects targets out of line of sight" do
      assert {:error, :line_of_sight} =
               CastValidation.validate(caster(), harmful_spell(), Target.unit(7), hostile_target(los?: false), @now)
    end

    test "requires a matching removable aura for non-periodic dispels" do
      cleanse =
        helpful_spell(
          name: "Cleanse",
          effects: [
            %Effect{type: :dispel, misc_value: 4, implicit_target_a: :target_ally},
            %Effect{type: :dispel, misc_value: 3, implicit_target_a: :target_ally},
            %Effect{type: :dispel, misc_value: 1, implicit_target_a: :target_ally}
          ]
        )

      assert {:error, :nothing_to_dispel} =
               CastValidation.validate(caster(), cleanse, Target.unit(7), friendly_target(), @now)

      assert :ok =
               CastValidation.validate(
                 caster(),
                 cleanse,
                 Target.unit(7),
                 friendly_target(dispel_options: MapSet.new([{3, :negative}])),
                 @now
               )

      assert {:error, :nothing_to_dispel} =
               CastValidation.validate(
                 caster(),
                 cleanse,
                 Target.unit(7),
                 friendly_target(dispel_options: MapSet.new([{1, :positive}])),
                 @now
               )
    end

    test "offensive dispels require a matching positive aura" do
      purge = harmful_spell(effects: [%Effect{type: :dispel, misc_value: 1, implicit_target_a: :target_enemy}])
      target = hostile_target(dispel_options: MapSet.new([{1, :positive}]))

      assert :ok = CastValidation.validate(caster(), purge, Target.unit(7), target, @now)
    end

    test "allows attacks with a secondary dispel against an unbuffed target" do
      shield_slam =
        harmful_spell(
          effects: [
            %Effect{type: :dispel, misc_value: 1, implicit_target_a: :target_enemy},
            %Effect{type: :school_damage, base_points: 225, implicit_target_a: :target_enemy}
          ]
        )

      assert :ok = CastValidation.validate(caster(), shield_slam, Target.unit(7), hostile_target(), @now)
    end

    test "allows area dispels without a removable aura on the selected target" do
      dispel =
        helpful_spell(
          effects: [%Effect{type: :dispel, misc_value: 1, radius_yards: 15.0, implicit_target_a: :target_ally}]
        )

      assert :ok = CastValidation.validate(caster(), dispel, Target.unit(7), friendly_target(), @now)
    end

    test "all-dispel accepts supported categories and excludes enrage" do
      for type <- [7, -1] do
        dispel = helpful_spell(effects: [%Effect{type: :dispel, misc_value: type, implicit_target_a: :target_ally}])

        for aura_type <- [1, 2, 3, 4] do
          target = friendly_target(dispel_options: MapSet.new([{aura_type, :negative}]))
          assert :ok = CastValidation.validate(caster(), dispel, Target.unit(7), target, @now)
        end

        target = friendly_target(dispel_options: MapSet.new([{9, :negative}]))
        assert {:error, :nothing_to_dispel} = CastValidation.validate(caster(), dispel, Target.unit(7), target, @now)
      end
    end

    test "rejects power burn against a different target resource" do
      mana_burn =
        harmful_spell(effects: [%Effect{type: :power_burn, misc_value: 0, implicit_target_a: :target_enemy}])

      assert :ok =
               CastValidation.validate(
                 caster(),
                 mana_burn,
                 Target.unit(7),
                 hostile_target(power_type: 0),
                 @now
               )

      assert {:error, :bad_targets} =
               CastValidation.validate(
                 caster(),
                 mana_burn,
                 Target.unit(7),
                 hostile_target(power_type: 1),
                 @now
               )
    end

    test "allows ignore_line_of_sight spells to bypass the LoS check" do
      spell = harmful_spell(attributes: MapSet.new([:ignore_line_of_sight]))

      assert :ok = CastValidation.validate(caster(), spell, Target.unit(7), hostile_target(los?: false), @now)
    end

    test "skips the LoS check when target info has no visibility fact" do
      assert :ok = CastValidation.validate(caster(), harmful_spell(), Target.unit(7), hostile_target(), @now)
    end

    test "rejects targets out of range or on another map" do
      out_of_range = hostile_target(position: {WorldRef.open(0), 100.0, 0.0, 0.0})
      other_map = hostile_target(position: {WorldRef.open(1), 10.0, 0.0, 0.0})

      assert {:error, :out_of_range} =
               CastValidation.validate(caster(), harmful_spell(), Target.unit(7), out_of_range, @now)

      assert {:error, :out_of_range} =
               CastValidation.validate(caster(), harmful_spell(), Target.unit(7), other_map, @now)
    end

    test "combat reach extends the maximum range" do
      barely_too_far = hostile_target(position: {WorldRef.open(0), 44.0, 0.0, 0.0})

      assert {:error, :out_of_range} =
               CastValidation.validate(caster(), harmful_spell(), Target.unit(7), barely_too_far, @now)

      big_target = Map.put(barely_too_far, :combat_reach, 4.0)
      long_arms = caster(combat_reach: 1.5)

      assert :ok = CastValidation.validate(long_arms, harmful_spell(), Target.unit(7), big_target, @now)
    end

    test "combat reach shrinks the distance measured against the minimum range" do
      charge = harmful_spell(min_range_yards: 8.0, range_yards: 25.0)
      target = hostile_target(position: {WorldRef.open(0), 10.0, 0.0, 0.0}, combat_reach: 4.0)

      assert {:error, :too_close} =
               CastValidation.validate(caster(combat_reach: 1.5), charge, Target.unit(7), target, @now)

      assert :ok = CastValidation.validate(caster(), charge, Target.unit(7), Map.delete(target, :combat_reach), @now)
    end

    test "skips the range check when the target position is unknown" do
      assert :ok =
               CastValidation.validate(
                 caster(),
                 harmful_spell(),
                 Target.unit(7),
                 hostile_target(position: nil),
                 @now
               )
    end
  end
end
