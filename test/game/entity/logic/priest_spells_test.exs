defmodule ThistleTea.Game.Entity.Logic.PriestSpellsTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.WorldRef

  @movement_flag_root 0x08000000
  @movement_flag_water_walk 0x10000000
  @movement_flag_safe_fall 0x20000000
  @movement_flag_hover 0x40000000
  @unit_flag_stunned 0x00040000

  @aura_interrupt_damage 0x02

  defp mob_fixture(opts \\ []) do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{
        level: Keyword.get(opts, :level, 10),
        health: Keyword.get(opts, :health, 100),
        max_health: 100,
        power1: Keyword.get(opts, :mana, 0),
        max_power1: Keyword.get(opts, :max_mana, 0),
        flags: 0,
        auras: []
      },
      internal: %Internal{world: %WorldRef{map_id: 0}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
    }
  end

  defp dead_player_fixture(opts \\ []) do
    ghost? = Keyword.get(opts, :ghost?, false)

    %Character{
      object: %Object{guid: 5},
      unit: %Unit{
        level: 10,
        health: if(ghost?, do: 1, else: 0),
        max_health: 100,
        power1: 0,
        max_power1: 80,
        auras: []
      },
      player: %Player{flags: if(ghost?, do: 0x10, else: 0)},
      internal: %Internal{world: %WorldRef{map_id: 0}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
    }
  end

  defp aura_spell(id, aura, opts) do
    %Spell{
      id: id,
      name: Keyword.get(opts, :name, "Spell #{id}"),
      school: Keyword.get(opts, :school, :holy),
      duration_ms: Keyword.get(opts, :duration_ms, 30_000),
      mechanic: Keyword.get(opts, :mechanic, 0),
      proc_type_mask: Keyword.get(opts, :proc_type_mask, 0),
      proc_charges: Keyword.get(opts, :proc_charges, 0),
      aura_interrupt_flags: Keyword.get(opts, :aura_interrupt_flags, 0),
      attributes: Keyword.get(opts, :attributes, MapSet.new()),
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          base_points: Keyword.get(opts, :base_points, 0),
          die_sides: Keyword.get(opts, :die_sides, 0),
          aura: aura,
          amplitude_ms: Keyword.get(opts, :amplitude_ms, 0),
          misc_value: Keyword.get(opts, :misc_value, 0),
          multiple_value: Keyword.get(opts, :multiple_value, 0.0),
          trigger_spell_id: Keyword.get(opts, :trigger_spell_id)
        }
      ]
    }
  end

  defp power_word_shield_fixture do
    %Spell{
      id: 17,
      name: "Power Word: Shield",
      script_name: "spell_priest_power_word_shield",
      school: :holy,
      duration_ms: 30_000,
      mechanic: 19,
      first_in_chain: 17,
      rank: 1,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          base_points: 43,
          die_sides: 1,
          aura: :school_absorb,
          misc_value: 127
        }
      ]
    }
  end

  defp weakened_soul_fixture do
    aura_spell(6788, :mechanic_immunity, name: "Weakened Soul", duration_ms: 15_000, misc_value: 19)
  end

  defp psychic_scream_fixture do
    %Spell{
      id: 8122,
      name: "Psychic Scream",
      school: :shadow,
      duration_ms: 8_000,
      mechanic: 5,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: :mod_fear,
          implicit_target_a: :aoe_enemy_at_caster,
          radius_yards: 8.0
        }
      ]
    }
  end

  defp shackle_fixture do
    aura_spell(9484, :mod_stun,
      name: "Shackle Undead",
      school: :holy,
      duration_ms: 30_000,
      mechanic: 20,
      aura_interrupt_flags: @aura_interrupt_damage
    )
  end

  describe "Power Word: Shield + Weakened Soul" do
    test "applying the shield queues a Weakened Soul trigger" do
      context = %CastContext{caster_guid: 999, caster_level: 10}

      {target, events} = SpellEffect.receive(mob_fixture(), context, power_word_shield_fixture(), 1_000)

      assert Aura.has_spell?(target, 17)

      assert [%{type: :trigger_spell, source_guid: 999, target_guid: 1, spell_id: 6788}] = events
    end

    test "Weakened Soul blocks reapplying the shield" do
      context = %CastContext{caster_guid: 999, caster_level: 10}
      {target, _events} = SpellEffect.receive(mob_fixture(), context, weakened_soul_fixture(), 1_000)

      {target, events} = SpellEffect.receive(target, context, power_word_shield_fixture(), 1_000)

      refute Aura.has_spell?(target, 17)
      assert events == []
    end

    test "mechanic_immune?/2 reports spells blocked by Weakened Soul" do
      context = %CastContext{caster_guid: 999, caster_level: 10}
      {target, _events} = SpellEffect.receive(mob_fixture(), context, weakened_soul_fixture(), 1_000)

      assert Aura.mechanic_immune?(target, power_word_shield_fixture())
      refute Aura.mechanic_immune?(target, psychic_scream_fixture())
    end

    test "shield absorbs damage across all schools" do
      context = %CastContext{caster_guid: 999, caster_level: 10}
      {target, _events} = SpellEffect.receive(mob_fixture(), context, power_word_shield_fixture(), 1_000)

      {target, remaining} = Aura.absorb_damage(target, 30, :shadow)

      assert remaining == 0
      assert Aura.has_spell?(target, 17)
    end
  end

  describe "Fear Ward (mechanic immunity charges)" do
    defp fear_ward_fixture do
      aura_spell(6346, :mechanic_immunity,
        name: "Fear Ward",
        duration_ms: 600_000,
        misc_value: 5,
        proc_charges: 1
      )
    end

    test "blocks an incoming fear and is consumed" do
      entity = mob_fixture()
      {entity, _events} = Aura.apply_spell(entity, 1, 10, fear_ward_fixture(), 1_000)

      {entity, _events} = Aura.apply_spell(entity, 999, 10, psychic_scream_fixture(), 2_000)

      refute Aura.has_aura?(entity, :mod_fear)
      refute Aura.has_spell?(entity, 6346)
    end

    test "removes an existing fear when applied" do
      entity = mob_fixture()
      {entity, _events} = Aura.apply_spell(entity, 999, 10, psychic_scream_fixture(), 1_000)
      assert Aura.has_aura?(entity, :mod_fear)

      {entity, _events} = Aura.apply_spell(entity, 1, 10, fear_ward_fixture(), 2_000)

      refute Aura.has_aura?(entity, :mod_fear)
      assert Aura.has_spell?(entity, 6346)
    end
  end

  describe "debuff attribute" do
    test "spells flagged aura-is-debuff land as uncancelable negative holders even on self" do
      weakened_soul = %{weakened_soul_fixture() | attributes: MapSet.new([:negative])}

      entity = mob_fixture()
      {entity, _events} = Aura.apply_spell(entity, 1, 10, weakened_soul, 1_000)

      assert [%Holder{negative?: true}] = entity.unit.auras

      {entity, _events} = Aura.cancel_spell(entity, 6788, 2_000)
      assert Aura.has_spell?(entity, 6788)
    end
  end

  describe "fear" do
    test "fear is a negative aura and anchors confused wandering" do
      entity = mob_fixture()
      {entity, _events} = Aura.apply_spell(entity, 999, 10, psychic_scream_fixture(), 1_000)

      assert [%Holder{negative?: true}] = entity.unit.auras
      assert Aura.confuse_anchor_key(entity) == {8122, 1_000}
    end

    test "fear without a damage interrupt flag survives damage" do
      entity = mob_fixture()
      {entity, _events} = Aura.apply_spell(entity, 999, 10, psychic_scream_fixture(), 1_000)

      entity = Aura.break_on_damage(entity, 2_000)

      assert Aura.has_aura?(entity, :mod_fear)
    end

    test "fear expires after its duration" do
      entity = mob_fixture()
      {entity, _events} = Aura.apply_spell(entity, 999, 10, psychic_scream_fixture(), 1_000)

      {entity, _events} = Aura.expire_due(entity, 9_001)

      refute Aura.has_aura?(entity, :mod_fear)
    end
  end

  describe "stun (Shackle Undead)" do
    test "stun roots, halts, and flags the unit as stunned" do
      entity = mob_fixture()
      {entity, events} = Aura.apply_spell(entity, 999, 10, shackle_fixture(), 1_000)

      assert (entity.movement_block.movement_flags &&& @movement_flag_root) != 0
      assert (entity.unit.flags &&& @unit_flag_stunned) != 0
      assert Enum.any?(events, &(&1.type == :movement_root_changed and &1.rooted?))
    end

    test "stun breaks on damage via its interrupt flags" do
      entity = mob_fixture()
      {entity, _events} = Aura.apply_spell(entity, 999, 10, shackle_fixture(), 1_000)

      entity = Core.take_damage(entity, 5, 2_000)

      refute Aura.has_aura?(entity, :mod_stun)
      assert (entity.movement_block.movement_flags &&& @movement_flag_root) == 0
      assert (entity.unit.flags &&& @unit_flag_stunned) == 0
    end

    test "a DoT tick on the same unit breaks the shackle" do
      entity = mob_fixture()
      {entity, _events} = Aura.apply_spell(entity, 999, 10, shackle_fixture(), 1_000)

      swp =
        aura_spell(589, :periodic_damage,
          name: "Shadow Word: Pain",
          school: :shadow,
          duration_ms: 18_000,
          base_points: 4,
          die_sides: 1,
          amplitude_ms: 3_000
        )

      {entity, _events} = Aura.apply_spell(entity, 999, 10, swp, 1_000)

      {entity, _events} = Aura.tick(entity, 4_100)

      refute Aura.has_aura?(entity, :mod_stun)
      assert Aura.has_spell?(entity, 589)
      assert entity.unit.health < 100
    end

    test "stun clears movement and unit flags when it expires" do
      entity = mob_fixture()
      {entity, _events} = Aura.apply_spell(entity, 999, 10, shackle_fixture(), 1_000)

      {entity, _events} = Aura.expire_due(entity, 32_000)

      assert (entity.movement_block.movement_flags &&& @movement_flag_root) == 0
      assert (entity.unit.flags &&& @unit_flag_stunned) == 0
    end
  end

  describe "Mana Burn (power_burn)" do
    defp mana_burn_fixture do
      %Spell{
        id: 8129,
        name: "Mana Burn",
        school: :shadow,
        effects: [
          %Effect{
            index: 0,
            type: :power_burn,
            base_points: 190,
            die_sides: 13,
            multiple_value: 0.5,
            implicit_target_a: :target_enemy
          }
        ]
      }
    end

    test "drains mana and deals half as damage" do
      target = mob_fixture(mana: 500, max_mana: 500)
      context = %CastContext{caster_guid: 999, caster_level: 24}

      {target, events} = SpellEffect.receive(target, context, mana_burn_fixture(), 1_000)

      drained = 500 - target.unit.power1
      assert drained in 191..203
      assert target.unit.health == max(100 - div(drained, 2), 0)
      assert [%{type: :spell_damage, damage: damage}] = events
      assert damage == div(drained, 2)
    end

    test "burns only the mana the target has" do
      target = mob_fixture(mana: 50, max_mana: 500)
      context = %CastContext{caster_guid: 999, caster_level: 24}

      {target, _events} = SpellEffect.receive(target, context, mana_burn_fixture(), 1_000)

      assert target.unit.power1 == 0
      assert target.unit.health == 100 - 25
    end

    test "does nothing against a target without mana" do
      target = mob_fixture(mana: 0, max_mana: 0)
      context = %CastContext{caster_guid: 999, caster_level: 24}

      {target, events} = SpellEffect.receive(target, context, mana_burn_fixture(), 1_000)

      assert target.unit.health == 100
      assert events == []
    end
  end

  describe "Devouring Plague (periodic_leech)" do
    defp devouring_plague_fixture do
      aura_spell(2944, :periodic_leech,
        name: "Devouring Plague",
        school: :shadow,
        duration_ms: 24_000,
        base_points: 17,
        die_sides: 1,
        amplitude_ms: 3_000,
        multiple_value: 1.0
      )
    end

    test "ticks deal damage and heal the caster for the same amount" do
      entity = mob_fixture()
      {entity, _events} = Aura.apply_spell(entity, 999, 10, devouring_plague_fixture(), 1_000)

      {entity, events} = Aura.tick(entity, 4_000)

      assert entity.unit.health == 100 - 18

      assert Enum.any?(events, &(&1.type == :spell_damage and &1.damage == 18 and &1.periodic?))
      assert Enum.any?(events, &(&1.type == :heal_entity and &1.target_guid == 999 and &1.amount == 18))
    end
  end

  describe "Levitate (hover + water walk + slow fall)" do
    defp levitate_fixture do
      %Spell{
        id: 1706,
        name: "Levitate",
        school: :holy,
        duration_ms: 120_000,
        aura_interrupt_flags: 0x20002,
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :feather_fall},
          %Effect{index: 1, type: :apply_aura, aura: :hover},
          %Effect{index: 2, type: :apply_aura, aura: :water_walk}
        ]
      }
    end

    test "sets safe fall, hover, and water walk movement flags with events" do
      entity = mob_fixture()
      {entity, events} = Aura.apply_spell(entity, 1, 10, levitate_fixture(), 1_000)

      flags = entity.movement_block.movement_flags
      assert (flags &&& @movement_flag_safe_fall) != 0
      assert (flags &&& @movement_flag_hover) != 0
      assert (flags &&& @movement_flag_water_walk) != 0

      assert Enum.any?(events, &(&1.type == :feather_fall_changed and &1.enabled?))
      assert Enum.any?(events, &(&1.type == :hover_changed and &1.enabled?))
      assert Enum.any?(events, &(&1.type == :water_walk_changed and &1.enabled?))
    end

    test "breaks on damage via its interrupt flags" do
      entity = mob_fixture()
      {entity, _events} = Aura.apply_spell(entity, 1, 10, levitate_fixture(), 1_000)

      entity = Core.take_damage(entity, 5, 2_000)

      flags = entity.movement_block.movement_flags
      assert (flags &&& @movement_flag_hover) == 0
      assert (flags &&& @movement_flag_water_walk) == 0
      refute Aura.has_spell?(entity, 1706)
    end
  end

  describe "resurrection (resurrect_new)" do
    defp resurrection_fixture do
      %Spell{
        id: 2006,
        name: "Resurrection",
        school: :holy,
        effects: [
          %Effect{index: 0, type: :resurrect_new, base_points: 69, die_sides: 1, misc_value: 135}
        ]
      }
    end

    test "queues a resurrect request on a dead player" do
      context = %CastContext{caster_guid: 999, caster_level: 10}

      {_target, events} = SpellEffect.receive(dead_player_fixture(), context, resurrection_fixture(), 1_000)

      assert [%{type: :resurrect_request, source_guid: 999, spell_id: 2006, health: 70, mana: 135}] = events
    end

    test "queues a resurrect request on a released ghost" do
      context = %CastContext{caster_guid: 999, caster_level: 10}

      {_target, events} =
        SpellEffect.receive(dead_player_fixture(ghost?: true), context, resurrection_fixture(), 1_000)

      assert [%{type: :resurrect_request}] = events
    end

    test "does nothing to living players or mobs" do
      context = %CastContext{caster_guid: 999, caster_level: 10}

      alive = %{dead_player_fixture() | unit: %Unit{health: 100, max_health: 100, auras: []}}
      {_target, events} = SpellEffect.receive(alive, context, resurrection_fixture(), 1_000)
      assert events == []

      {_target, events} = SpellEffect.receive(mob_fixture(health: 0), context, resurrection_fixture(), 1_000)
      assert events == []
    end

    test "cast validation requires a dead friendly target" do
      caster = mob_fixture()
      spell = resurrection_fixture()
      targets = Targets.unit(5)

      assert {:error, :target_not_dead} =
               CastValidation.validate(caster, spell, targets, %{alive?: true, friendly?: true}, 1_000)

      assert {:error, :target_enemy} =
               CastValidation.validate(caster, spell, targets, %{alive?: false, hostile?: true}, 1_000)

      assert :ok = CastValidation.validate(caster, spell, targets, %{alive?: false, friendly?: true}, 1_000)
    end
  end

  describe "aura charges on hit" do
    defp inner_fire_fixture do
      aura_spell(588, :mod_resistance,
        name: "Inner Fire",
        duration_ms: 600_000,
        base_points: 314,
        misc_value: 1,
        proc_charges: 20
      )
    end

    defp shadowguard_fixture do
      aura_spell(18_137, :proc_trigger_spell,
        name: "Shadowguard",
        school: :shadow,
        duration_ms: 600_000,
        proc_type_mask: 0x8,
        proc_charges: 3,
        trigger_spell_id: 28_376
      )
    end

    test "Inner Fire loses a charge per melee hit taken" do
      entity = mob_fixture()
      {entity, _events} = Aura.apply_spell(entity, 1, 10, inner_fire_fixture(), 1_000)

      {entity, _events} = Aura.reactions(entity, :hit_taken, %{attacker_guid: 999})

      assert [%Holder{charges: 19}] = entity.unit.auras
    end

    test "the holder is removed when the last charge is spent" do
      entity = mob_fixture()
      spell = %{shadowguard_fixture() | proc_charges: 1}
      {entity, _events} = Aura.apply_spell(entity, 1, 10, spell, 1_000)

      {entity, events} = Aura.reactions(entity, :hit_taken, %{attacker_guid: 999})

      assert Enum.any?(events, &(&1.type == :trigger_spell and &1.spell_id == 28_376))
      assert entity.unit.auras == []
    end

    test "Shadowguard procs and decrements through receive_attack" do
      entity = mob_fixture()
      {entity, _events} = Aura.apply_spell(entity, 1, 10, shadowguard_fixture(), 1_000)

      {entity, events} = Combat.receive_attack(entity, %{caster: 999, damage: 5}, 2_000, roll: 9_999)

      assert Enum.any?(events, &(&1.type == :trigger_spell and &1.spell_id == 28_376))
      assert [%Holder{charges: 2}] = entity.unit.auras
    end

    test "holders without charges are untouched by hits" do
      entity = mob_fixture()
      spell = %{inner_fire_fixture() | proc_charges: 0}
      {entity, _events} = Aura.apply_spell(entity, 1, 10, spell, 1_000)

      {entity, _events} = Aura.reactions(entity, :hit_taken, %{attacker_guid: 999})

      assert [%Holder{charges: nil}] = entity.unit.auras
    end
  end

  describe "healing modifiers" do
    defp lesser_heal_fixture do
      %Spell{
        id: 2050,
        name: "Lesser Heal",
        school: :holy,
        cast_time_ms: 1_500,
        effects: [
          %Effect{index: 0, type: :heal, base_points: 46, die_sides: 1, implicit_target_a: :target_ally}
        ]
      }
    end

    test "mod_healing_pct reduces incoming heals (Hex of Weakness)" do
      entity = mob_fixture(health: 10)

      hex =
        aura_spell(9035, :mod_healing_pct,
          name: "Hex of Weakness",
          school: :shadow,
          duration_ms: 120_000,
          base_points: -21,
          misc_value: 127
        )

      {entity, _events} = Aura.apply_spell(entity, 999, 10, hex, 1_000)

      context = %CastContext{caster_guid: 999, caster_level: 10}
      {entity, _events} = SpellEffect.receive(entity, context, lesser_heal_fixture(), 1_000)

      assert entity.unit.health == 10 + trunc(47 * 0.8)
    end

    test "mod_resistance_exclusive raises the school resistance (Shadow Protection)" do
      entity = mob_fixture()

      shadow_protection =
        aura_spell(976, :mod_resistance_exclusive,
          name: "Shadow Protection",
          duration_ms: 600_000,
          base_points: 29,
          die_sides: 1,
          misc_value: 32
        )

      {entity, _events} = Aura.apply_spell(entity, 1, 10, shadow_protection, 1_000)

      assert entity.unit.shadow_resistance == 30
      assert entity.unit.normal_resistance == 0
    end
  end

  describe "dispel polarity" do
    defp magic_buff_fixture do
      aura_spell(1243, :mod_stat, name: "Power Word: Fortitude", duration_ms: 1_800_000, base_points: 3, misc_value: 2)
      |> Map.put(:dispel_type, 1)
    end

    defp magic_debuff_fixture do
      aura_spell(589, :periodic_damage,
        name: "Shadow Word: Pain",
        school: :shadow,
        duration_ms: 18_000,
        base_points: 5,
        amplitude_ms: 3_000
      )
      |> Map.put(:dispel_type, 1)
    end

    test "offensive dispel removes a buff, not the caster's own debuff" do
      entity = mob_fixture()
      {entity, _events} = Aura.apply_spell(entity, 1, 10, magic_buff_fixture(), 1_000)
      {entity, _events} = Aura.apply_spell(entity, 999, 10, magic_debuff_fixture(), 1_000)

      {entity, _events} = Aura.dispel(entity, 1, 2_000, :positive)

      refute Aura.has_spell?(entity, 1243)
      assert Aura.has_spell?(entity, 589)
    end

    test "defensive dispel removes a debuff, not a buff" do
      entity = mob_fixture()
      {entity, _events} = Aura.apply_spell(entity, 1, 10, magic_buff_fixture(), 1_000)
      {entity, _events} = Aura.apply_spell(entity, 999, 10, magic_debuff_fixture(), 1_000)

      {entity, _events} = Aura.dispel(entity, 1, 2_000, :negative)

      assert Aura.has_spell?(entity, 1243)
      refute Aura.has_spell?(entity, 589)
    end
  end

  describe "periodic trigger spell auras (Abolish Disease)" do
    defp abolish_disease_fixture do
      %Spell{
        id: 552,
        name: "Abolish Disease",
        school: :shadow,
        duration_ms: 20_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: :periodic_trigger_spell,
            amplitude_ms: 5_000,
            trigger_spell_id: 10_872,
            implicit_target_a: :target_ally
          },
          %Effect{index: 1, type: :dispel, misc_value: 3, implicit_target_a: :target_ally}
        ]
      }
    end

    test "non-channeled periodic triggers apply as a ticking aura" do
      entity = mob_fixture()
      context = %CastContext{caster_guid: 999, caster_level: 10}

      {entity, events} = SpellEffect.receive(entity, context, abolish_disease_fixture(), 1_000)

      assert Aura.has_spell?(entity, 552)
      assert events == []

      {entity, events} = Aura.tick(entity, 6_000)

      assert Enum.any?(events, &(&1.type == :trigger_spell and &1.spell_id == 10_872))
      assert Aura.has_spell?(entity, 552)
    end
  end

  describe "Mind Soothe (mod_detect_range)" do
    test "applies as a negative aura with the detection penalty" do
      entity = mob_fixture()

      mind_soothe =
        aura_spell(453, :mod_detect_range,
          name: "Mind Soothe",
          duration_ms: 15_000,
          base_points: -11,
          die_sides: 1
        )

      {entity, _events} = Aura.apply_spell(entity, 999, 10, mind_soothe, 1_000)

      assert [%Holder{negative?: true}] = entity.unit.auras
      assert [%{amount: -10}] = Aura.auras_of_type(entity, :mod_detect_range)
    end
  end

  describe "self-cast immunity validation" do
    test "recasting Power Word: Shield on self while Weakened Soul is active fails with :immune" do
      caster = dead_player_fixture()
      caster = %{caster | unit: %{caster.unit | health: 100}}

      {caster, _events} = Aura.apply_spell(caster, 5, 10, weakened_soul_fixture(), 1_000)

      targets = Targets.unit(5)

      assert {:error, :immune} =
               CastValidation.validate(caster, power_word_shield_fixture(), targets, :self, 1_000)
    end
  end
end
