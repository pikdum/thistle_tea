defmodule ThistleTea.Game.Entity.Logic.PaladinSpellsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Paladin
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  describe "release_seal/4" do
    test "consumes the active seal and triggers its judgement spell" do
      seal = %Spell{id: 20_154, name: "Seal of Righteousness", exclusive_category: :paladin_seal}

      character =
        character([
          %Holder{
            spell: seal,
            caster_guid: 5,
            auras: [%Aura{index: 2, type: :dummy, amount: 20_192}]
          }
        ])

      judgement = %Spell{id: 20_271, spell_family: 10, family_flags_0: 0x00800000}
      result = Paladin.release_seal(character, judgement, 9, 1_000)

      assert result.unit.auras == []
      assert Enum.any?(result.internal.events, &(&1.type == :trigger_spell and &1.spell_id == 20_192))
      assert result.internal.broadcast_update?
    end

    test "leaves seals untouched for other spells" do
      seal = %Spell{id: 20_154, exclusive_category: :paladin_seal}
      character = character([%Holder{spell: seal, auras: [%Aura{index: 2, type: :dummy, amount: 20_192}]}])

      assert Paladin.release_seal(character, %Spell{id: 853}, 9, 1_000) == character
    end
  end

  describe "Hammer of Wrath" do
    test "uses melee crit because the VMangos script overrides its ranged damage class" do
      caster = character([])
      caster = %{caster | unit: %{caster.unit | class: 2}}
      caster = %{caster | player: %{caster.player | ranged_crit_percentage: 40.0}}
      spell = %Spell{id: 24_239, script_name: "spell_paladin_hammer_of_wrath", school: :holy, dmg_class: 3}

      context = CastContext.from_caster(caster, spell, 9)

      assert_in_delta context.spell_crit_chance, 0.7, 0.001
    end
  end

  describe "Judgement validation" do
    @describetag :dbc_db

    test "accepts a DBC Judgement cast while a DBC Seal is active" do
      seal = SpellLoader.load(21_084)
      judgement = SpellLoader.load(20_271)
      caster_context = %CastContext{caster_guid: 5, caster_level: 60, target_guid: 5}
      {caster, _events} = AuraLogic.apply_spell(character([]), caster_context, seal, 1_000)

      assert Paladin.active_seal?(caster)
      assert Bitwise.band(caster.unit.aura_state, 0x10) != 0

      target_info = %{
        guid: 9,
        alive?: true,
        hostile?: true,
        friendly?: false,
        attackable?: true,
        position: {0, 1.0, 0.0, 0.0},
        los?: true
      }

      assert :ok = CastValidation.validate(caster, judgement, Targets.unit(9), target_info, 2_000)
    end

    test "released DBC judgements damage or apply their aura to the victim" do
      judgement = SpellLoader.load(20_271)

      Enum.each([{21_084, :damage}, {20_165, :aura}], fn {seal_id, expected} ->
        seal = SpellLoader.load(seal_id)
        caster_context = %CastContext{caster_guid: 5, caster_level: 60, target_guid: 5}
        {caster, _events} = AuraLogic.apply_spell(character([]), caster_context, seal, 1_000)
        caster = Paladin.release_seal(caster, judgement, 9, 2_000)
        trigger = Enum.find(caster.internal.events, &(&1.type == :trigger_spell))
        triggered_spell = SpellLoader.load(trigger.spell_id)

        target = character([])
        target = %{target | object: %Object{guid: 9}, unit: %{target.unit | health: 10_000, max_health: 10_000}}

        context = %CastContext{
          caster_guid: trigger.source_guid,
          caster_level: trigger.source_level,
          target_guid: 9,
          target_hostile?: true
        }

        {target, _events} = SpellEffect.receive(target, context, triggered_spell, 2_000)

        case expected do
          :damage ->
            assert target.unit.health < 10_000

          :aura ->
            assert Enum.any?(target.unit.auras, &(&1.spell.id == trigger.spell_id and &1.negative?))
        end
      end)
    end
  end

  describe "school immunity" do
    test "Divine Shield-style immunity prevents all damage" do
      bubble = %Holder{
        spell: %Spell{id: 642},
        auras: [%Aura{type: :school_immunity, misc_value: 0x7F}]
      }

      character = character([bubble])

      assert {^character, 50} = Core.take_damage_with_absorb(character, 50, 1_000, school: :physical)
      assert {^character, 50} = Core.take_damage_with_absorb(character, 50, 1_000, school: :shadow)
    end

    test "Blessing of Protection-style immunity only prevents physical damage" do
      protection = %Holder{
        spell: %Spell{id: 1022},
        auras: [%Aura{type: :school_immunity, misc_value: 0x1}]
      }

      character = character([protection])

      assert {^character, 50} = Core.take_damage_with_absorb(character, 50, 1_000, school: :physical)

      assert {%Character{unit: %Unit{health: 50}}, 0} =
               Core.take_damage_with_absorb(character, 50, 1_000, school: :holy)
    end

    test "Divine Shield rejects hostile aura spells as immune" do
      bubble = %Holder{
        spell: %Spell{id: 642},
        auras: [%Aura{type: :school_immunity, misc_value: 0x7F}]
      }

      target = character([bubble])

      stun = %Spell{
        id: 853,
        school: :holy,
        effects: [
          %Spell.Effect{index: 0, type: :apply_aura, aura: :mod_stun, implicit_target_a: :target_enemy}
        ]
      }

      context = %CastContext{caster_guid: 9, caster_level: 60, target_hostile?: true}

      assert {^target, [%{type: :spell_log_miss, reason: :immune}]} = SpellEffect.receive(target, context, stun, 1_000)
    end
  end

  describe "blessing ownership" do
    test "one paladin's blessing replaces their previous blessing without removing another paladin's" do
      might = blessing(19_740, "Blessing of Might")
      wisdom = blessing(19_742, "Blessing of Wisdom")
      light = blessing(19_977, "Blessing of Light")
      target = character([])

      {target, _events} = AuraLogic.apply_spell(target, 5, 60, might, 1_000)
      {target, _events} = AuraLogic.apply_spell(target, 6, 60, wisdom, 1_000)
      {target, _events} = AuraLogic.apply_spell(target, 5, 60, light, 2_000)

      assert Enum.map(target.unit.auras, &{&1.spell.id, &1.caster_guid}) == [{19_742, 6}, {19_977, 5}]
    end
  end

  describe "party auras" do
    test "the caster owns refresh ticks while remote applications expire as leases" do
      spell = %Spell{
        id: 465,
        name: "Devotion Aura",
        duration_ms: 0,
        exclusive_category: :paladin_aura,
        effects: [
          %Spell.Effect{
            index: 0,
            type: :apply_area_aura,
            aura: :mod_resistance,
            base_points: 55,
            radius_yards: 30.0
          }
        ]
      }

      caster_context = %CastContext{caster_guid: 5, caster_level: 60, target_guid: 5}
      {caster, _events} = AuraLogic.apply_spell(character([]), caster_context, spell, 1_000)
      [caster_holder] = caster.unit.auras

      assert caster_holder.expires_at == nil
      assert caster_holder.area_radius == 30.0
      assert caster_holder.next_area_refresh_at == 2_000

      remote = character([])
      remote = %{remote | object: %Object{guid: 9}}
      remote_context = %{caster_context | target_guid: 9}
      {remote, _events} = AuraLogic.apply_spell(remote, remote_context, spell, 1_000)
      [remote_holder] = remote.unit.auras

      assert remote_holder.expires_at == 3_500
      assert remote_holder.next_area_refresh_at == nil

      {_caster, events} = AuraLogic.tick(caster, 2_000)
      assert [%{type: :refresh_party_aura, spell: ^spell, amount: 30.0}] = events
    end
  end

  describe "trigger_seal/2" do
    test "Seal of Righteousness deals speed-scaled holy damage on a landed melee hit" do
      seal = %Spell{id: 20_287, name: "Seal of Righteousness", exclusive_category: :paladin_seal}

      character =
        character([
          %Holder{spell: seal, auras: [%Aura{index: 0, type: :dummy, amount: 216}]}
        ])

      result = Paladin.trigger_seal(character, %{outcome: :normal, victim_guid: 9})

      assert [event] = result.internal.events
      assert event.type == :deliver_spell
      assert event.target_guid == 9
      assert event.spell.id == 25_740
      assert event.spell.school == :holy
      assert [%Spell.Effect{type: :school_damage, base_points: 3}] = event.spell.effects
    end

    test "does not trigger a seal from an avoided hit" do
      seal = %Spell{id: 20_287, name: "Seal of Righteousness", exclusive_category: :paladin_seal}
      character = character([%Holder{spell: seal, auras: [%Aura{index: 0, type: :dummy, amount: 216}]}])

      assert Paladin.trigger_seal(character, %{outcome: :miss, victim_guid: 9}) == character
    end

    test "Seal of Light heals only the paladin wielding the seal" do
      seal = %Spell{
        id: 20_165,
        name: "Seal of Light",
        spell_family: 10,
        family_flags_0: 0x08000000,
        exclusive_category: :paladin_seal,
        proc_type_mask: 20
      }

      character =
        character([
          %Holder{spell: seal, auras: [%Aura{index: 0, type: :proc_trigger_spell, trigger_spell_id: 20_167}]}
        ])

      result = Paladin.trigger_seal(character, %{outcome: :normal, victim_guid: 9})

      assert [%{type: :trigger_spell, source_guid: 5, target_guid: 9, spell_id: 20_167}] = result.internal.events

      assert {_character, []} = AuraLogic.reactions(character, :hit_taken, %{attacker_guid: 9})
    end
  end

  describe "scripted spell effects" do
    test "Holy Shock selects its healing spell for a friendly target" do
      spell = %Spell{
        id: 20_473,
        name: "Holy Shock",
        script_name: "spell_paladin_holy_shock",
        effects: [%Spell.Effect{index: 0, type: :dummy}]
      }

      context = %CastContext{caster_guid: 5, caster_level: 60, target_hostile?: false}
      target = character([])
      target = %{target | object: %Object{guid: 9}}

      assert {_target, [%{type: :trigger_spell, spell_id: 25_914, target_guid: 9}]} =
               SpellEffect.receive(target, context, spell, 1_000)
    end

    test "Divine Intervention's DBC instakill effect kills only the caster target" do
      caster = character([])
      spell = %Spell{id: 19_752, effects: [%Spell.Effect{type: :instakill, implicit_target_a: :caster}]}
      context = %CastContext{caster_guid: 5, caster_level: 60}

      assert {%Character{unit: %Unit{health: 0}}, _events} = SpellEffect.receive(caster, context, spell, 1_000)

      ally = character([])
      ally = %{ally | object: %Object{guid: 9}}
      assert {^ally, []} = SpellEffect.receive(ally, context, spell, 1_000)
    end

    test "Judgement of Command triggers the damage spell encoded in its dummy effect" do
      spell = %Spell{
        id: 20_425,
        name: "Judgement of Command",
        script_name: "spell_paladin_judgement_of_command_dummy",
        spell_family: 10,
        spell_icon: 561,
        effects: [%Spell.Effect{index: 0, type: :dummy, base_points: 20_466}]
      }

      context = %CastContext{caster_guid: 5, caster_level: 60, target_hostile?: true}
      target = character([])
      target = %{target | object: %Object{guid: 9}}

      assert {_target, [%{type: :trigger_spell, spell_id: 20_466, target_guid: 9}]} =
               SpellEffect.receive(target, context, spell, 1_000)
    end

    test "Blessing of Light increases Holy Light by its first dummy amount" do
      blessing = %Holder{
        spell: %Spell{id: 19_977, name: "Blessing of Light", spell_family: 10, family_flags_0: 0x10000000},
        auras: [%Aura{index: 0, type: :dummy, amount: 210}, %Aura{index: 1, type: :dummy, amount: 60}]
      }

      target = character([blessing])
      target = %{target | unit: %{target.unit | health: 100, max_health: 1_000}}

      spell = %Spell{
        id: 639,
        name: "Holy Light",
        spell_family: 10,
        family_flags_0: 0x80000000,
        school: :holy,
        effects: [%Spell.Effect{type: :heal, base_points: 100}]
      }

      context = %CastContext{caster_guid: 5, caster_level: 60}

      assert {%Character{unit: %Unit{health: 410}}, _events} = SpellEffect.receive(target, context, spell, 1_000)
    end
  end

  describe "aura-derived effects" do
    test "Blessing of Kings increases all canonical stats by ten percent" do
      kings = %Spell{
        id: 20_217,
        exclusive_category: :paladin_blessing,
        effects: [
          %Spell.Effect{index: 0, type: :apply_aura, aura: :mod_total_stat_percent, base_points: 10, misc_value: -1}
        ]
      }

      target = character([])
      target = %{target | unit: %{target.unit | base_strength: 100, strength: 100}}
      {target, _events} = AuraLogic.apply_spell(target, 5, 60, kings, 1_000)

      assert target.unit.strength == 110
    end

    test "Retribution Aura retaliates through the normal spell delivery path" do
      retribution = %Holder{
        spell: %Spell{id: 7294, name: "Retribution Aura", school: :holy},
        caster_guid: 5,
        caster_level: 60,
        auras: [%Aura{type: :damage_shield, amount: 5}]
      }

      {target, [event]} = AuraLogic.reactions(character([retribution]), :hit_taken, %{attacker_guid: 9})

      assert target.unit.auras == [retribution]
      assert event.type == :deliver_spell
      assert event.target_guid == 9
      assert event.spell.school == :holy
      assert [%Spell.Effect{type: :school_damage, base_points: 5}] = event.spell.effects
    end

    test "Blessing of Sacrifice redirects its flat per-hit amount to the paladin" do
      sacrifice = %Holder{
        spell: %Spell{id: 6940, name: "Blessing of Sacrifice"},
        caster_guid: 7,
        auras: [%Aura{type: :split_damage_flat, amount: 44, misc_value: 0x7F}]
      }

      target = character([sacrifice])
      damaged = Core.take_damage(target, 100, 1_000, school: :shadow, source: 9)

      assert damaged.unit.health == 45

      assert Enum.any?(damaged.internal.events, fn event ->
               event.type == :redirect_damage and event.source_guid == 9 and event.target_guid == 7 and
                 event.amount == 45
             end)
    end
  end

  defp character(auras) do
    %Character{
      object: %Object{guid: 5},
      unit: %Unit{level: 60, health: 100, max_health: 100, auras: auras},
      player: %Player{},
      internal: %Internal{}
    }
  end

  defp blessing(id, name) do
    %Spell{
      id: id,
      name: name,
      duration_ms: 300_000,
      exclusive_category: :paladin_blessing,
      effects: [%Spell.Effect{index: 0, type: :apply_aura, aura: :mod_attack_power, base_points: 10}]
    }
  end
end
