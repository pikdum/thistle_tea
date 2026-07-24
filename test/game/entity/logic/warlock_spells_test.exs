defmodule ThistleTea.Game.Entity.Logic.WarlockSpellsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet, as: PetBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.World.Loader.SpellPetAura
  alias ThistleTea.Game.WorldRef

  describe "Life Tap" do
    test "converts health into mana without killing the caster" do
      caster = character(health: 100, power1: 0, max_power1: 200)

      spell = %Spell{
        id: 1454,
        name: "Life Tap",
        script_name: "spell_warlock_life_tap",
        school: :shadow,
        spell_family: 5,
        family_flags_0: 0x00040000,
        effects: [%Effect{type: :dummy, base_points: 39}]
      }

      context = %CastContext{caster_guid: 1, caster_level: 20, spell_damage_bonus: %{}}

      {result, _events} = SpellEffect.receive(caster, context, spell, 1_000)

      assert result.unit.health == 61
      assert result.unit.power1 == 39
    end

    test "improved life tap boosts the mana gained" do
      talent = %Holder{
        slot: 0,
        caster_guid: 1,
        spell: %Spell{id: 18_183, name: "Improved Life Tap"},
        auras: [%Aura{type: :dummy, amount: 20}]
      }

      caster = character(health: 100, power1: 0, max_power1: 200, auras: [talent])

      spell = %Spell{
        id: 1454,
        name: "Life Tap",
        script_name: "spell_warlock_life_tap",
        school: :shadow,
        spell_family: 5,
        family_flags_0: 0x00040000,
        effects: [%Effect{type: :dummy, base_points: 39}]
      }

      context = %CastContext{caster_guid: 1, caster_level: 20, spell_damage_bonus: %{}}

      {result, _events} = SpellEffect.receive(caster, context, spell, 1_000)

      assert result.unit.health == 61
      assert result.unit.power1 == 46
    end
  end

  describe "Soul Link pet auras" do
    test "the dummy cast places the linked aura on the active pet" do
      SpellPetAura.init()
      :ets.insert(SpellPetAura, {19_028, [{0, 25_228}]})

      pet_guid = 999
      caster = character()
      caster = %{caster | unit: %{caster.unit | summon: pet_guid}}

      soul_link = %Spell{id: 19_028, name: "Soul Link", effects: [%Effect{type: :dummy, base_points: 0}]}
      context = %CastContext{caster_guid: 1, caster_level: 40}

      {_result, events} = SpellEffect.receive(caster, context, soul_link, 1_000)

      assert Enum.any?(events, &(&1.type == :trigger_spell and &1.spell_id == 25_228 and &1.target_guid == pet_guid))
    end
  end

  describe "Healthstone creation" do
    test "turns the rank script effect into the matching item event" do
      spell = %Spell{
        id: 6201,
        name: "Create Healthstone (Minor)",
        script_name: "spell_warlock_create_healthstone",
        effects: [%Effect{type: :script_effect}]
      }

      context = %CastContext{caster_guid: 1, caster_level: 20}

      {_result, events} = SpellEffect.receive(character(), context, spell, 1_000)

      assert Enum.any?(events, &(&1.type == :create_item and &1.item_id == 5512))
    end

    test "does not apply the VMangos item table without its script label" do
      spell = %Spell{id: 6201, effects: [%Effect{type: :script_effect}]}
      context = %CastContext{caster_guid: 1, caster_level: 20}

      {_result, events} = SpellEffect.receive(character(), context, spell, 1_000)

      refute Enum.any?(events, &(&1.type == :create_item))
    end
  end

  describe "Inferno and demon control" do
    test "summon possessed uses the effect data and selected destination" do
      eye = %Spell{
        id: 126,
        duration_ms: 60_000,
        effects: [%Effect{type: :summon_possessed, misc_value: 4277, implicit_target_a: :minion_position}]
      }

      context = %CastContext{
        caster_guid: 1,
        caster_level: 22,
        caster_position: {%WorldRef{map_id: 0}, 1.0, 2.0, 3.0},
        caster_orientation: 0.5,
        target_role: :caster
      }

      {_result, [%{type: :summon_creature, summon: summon}]} =
        SpellEffect.receive(character(), context, eye, 1_000)

      assert summon.entry == 4277
      {x, y, z, orientation} = summon.position
      assert_in_delta x, 1.0 + 0.5 * :math.cos(0.5), 0.0001
      assert_in_delta y, 2.0 + 0.5 * :math.sin(0.5), 0.0001
      assert z == 3.0
      assert orientation == 0.5
      assert summon.control == :possessed
      assert summon.control_spell_id == 126
      assert summon.despawn_delay_ms == 60_000
    end

    test "Inferno carries only the VMangos post-summon spell script" do
      inferno = %Spell{
        id: 1122,
        script_name: "spell_warlock_inferno",
        duration_ms: 300_000,
        effects: [%Effect{type: :summon_demon, misc_value: 89}]
      }

      context = %CastContext{
        caster_guid: 1,
        caster_level: 60,
        caster_position: {%WorldRef{map_id: 0}, 1.0, 2.0, 3.0},
        caster_orientation: 0.5
      }

      {_result, [%{type: :summon_creature, summon: summon}]} =
        SpellEffect.receive(character(), context, inferno, 1_000)

      assert summon.post_spawn_spells == [
               %{caster: :owner, spell_id: 20_882, resolve_targets?: false},
               %{caster: :summon, spell_id: 22_707, resolve_targets?: false},
               %{caster: :summon, spell_id: 22_703, resolve_targets?: true}
             ]

      ordinary = %{inferno | script_name: nil}
      {_result, [%{summon: ordinary_summon}]} = SpellEffect.receive(character(), context, ordinary, 1_000)
      assert ordinary_summon.post_spawn_spells == []
    end

    test "a possess aura drives mob control and restores the original state on removal" do
      enslave = %Spell{
        id: 20_882,
        duration_ms: 300_000,
        effects: [%Effect{type: :apply_aura, aura: :mod_charm, base_points: 60}]
      }

      context = %CastContext{
        caster_guid: 1,
        caster_level: 60,
        caster_faction_template: 35,
        target_guid: 2,
        spell: enslave
      }

      original = mob()
      original = %{original | unit: %{original.unit | faction_template: 14, npc_flags: 7}}
      {controlled, events} = SpellEffect.receive(original, context, enslave, 1_000)

      assert controlled.unit.charmed_by == 1
      assert controlled.unit.faction_template == 35
      assert controlled.unit.npc_flags == 0
      assert controlled.internal.pet.owner_guid == 1
      assert controlled.internal.pet.kind == :charmed
      assert Enum.any?(events, &(&1.type == :control_granted and &1.spell_id == 20_882))

      {released, events} = AuraLogic.remove_spells(controlled, [20_882], 2_000)

      assert released.unit.charmed_by == 0
      assert released.unit.faction_template == 14
      assert released.unit.npc_flags == 7
      assert released.internal.pet == nil
      assert Enum.any?(events, &(&1.type == :control_released and &1.target_guid == 2))
    end
  end

  describe "Death Coil" do
    test "damages the target and heals the caster" do
      spell = %Spell{
        id: 6789,
        name: "Death Coil",
        school: :shadow,
        effects: [%Effect{type: :health_leech, base_points: 49}]
      }

      context = %CastContext{caster_guid: 1, caster_level: 40, spell_damage_bonus: %{}}

      {target, events} = SpellEffect.receive(mob(), context, spell, 1_000)

      assert target.unit.health == 151
      assert Enum.any?(events, &(&1.type == :heal_entity and &1.target_guid == 1 and &1.amount == 49))
    end
  end

  describe "Devour Magic" do
    test "heals the felhunter after a successful dispel" do
      buff = %Holder{
        spell: %Spell{id: 100, dispel_type: 1},
        caster_guid: 2,
        slot: 0,
        auras: [%Aura{type: :mod_stat, amount: 10}]
      }

      devour = %Spell{
        id: 19_505,
        script_name: "spell_warlock_devour_magic",
        effects: [%Effect{index: 0, type: :dispel, misc_value: 1}]
      }

      context = %CastContext{caster_guid: 1, caster_level: 40, target_hostile?: true}
      {target, events} = SpellEffect.receive(mob([buff]), context, devour, 1_000)

      assert target.unit.auras == []

      assert Enum.any?(events, fn event ->
               event.type == :trigger_spell and event.source_guid == 1 and event.target_guid == 1 and
                 event.spell_id == 19_658
             end)
    end

    test "does not heal when nothing was dispelled" do
      devour = %Spell{
        id: 19_505,
        script_name: "spell_warlock_devour_magic",
        effects: [%Effect{index: 0, type: :dispel, misc_value: 1}]
      }

      context = %CastContext{caster_guid: 1, caster_level: 40, target_hostile?: true}
      {_target, events} = SpellEffect.receive(mob(), context, devour, 1_000)

      refute Enum.any?(events, &(&1.type == :trigger_spell))
    end
  end

  describe "Ritual of Summoning" do
    test "requires a grouped player target outside combat" do
      ritual = %Spell{id: 698, script_name: "spell_warlock_ritual_of_summoning"}

      valid = %{
        target_player?: true,
        target_online?: true,
        self?: false,
        same_group?: true,
        target_in_combat?: false,
        caster_dungeon?: false,
        caster_battleground?: false,
        same_world?: false
      }

      assert :ok = CastValidation.validate(character(), ritual, %Targets{}, nil, 1_000, ritual_context: valid)

      assert {:error, :target_in_combat} =
               CastValidation.validate(character(), ritual, %Targets{}, nil, 1_000,
                 ritual_context: %{valid | target_in_combat?: true}
               )

      assert {:error, :target_not_in_instance} =
               CastValidation.validate(character(), ritual, %Targets{}, nil, 1_000,
                 ritual_context: %{valid | caster_dungeon?: true}
               )

      assert {:error, :not_here} =
               CastValidation.validate(character(), ritual, %Targets{}, nil, 1_000,
                 ritual_context: %{valid | caster_battleground?: true}
               )

      assert {:error, :bad_targets} =
               CastValidation.validate(character(), ritual, %Targets{}, nil, 1_000,
                 ritual_context: %{valid | same_group?: false}
               )
    end

    test "spawns a data-driven ritual object when channeling begins" do
      ritual = %Spell{
        id: 698,
        script_name: "spell_warlock_ritual_of_summoning",
        duration_ms: 120_000,
        attributes: MapSet.new([:channeled]),
        effects: [%Effect{index: 0, type: :trans_door, misc_value: 36_727}]
      }

      caster = character()
      caster = %{caster | unit: %{caster.unit | target: 9}}
      caster = SpellBT.start_cast(caster, ritual, %Targets{}, 1_000)

      assert Enum.any?(caster.internal.events, fn event ->
               event.type == :summon_game_object and event.entry == 36_727 and event.target_guid == 9 and
                 event.duration_ms == 120_000
             end)
    end

    test "cancelling a channel despawns its tracked game object" do
      ritual = %Spell{
        id: 698,
        duration_ms: 120_000,
        attributes: MapSet.new([:channeled]),
        effects: []
      }

      caster = SpellBT.start_cast(character(), ritual, %Targets{}, 1_000)

      caster = %{
        caster
        | internal: %{
            caster.internal
            | channel_game_object_guid: 77,
              channel_game_object_owned?: true
          }
      }

      caster = SpellBT.clear_cast(caster)

      assert caster.internal.channel_game_object_guid == nil
      assert Enum.any?(caster.internal.events, &(&1.type == :despawn_entity and &1.target_guid == 77))
    end

    test "helper channel cancellation releases the participant without despawning the portal" do
      visual = %Spell{id: 698, duration_ms: 120_000, attributes: MapSet.new([:channeled])}

      helper = SpellBT.start_game_object_channel(character(), 77, visual, 120_000, 1_000)
      helper = SpellBT.clear_cast(helper)

      assert Enum.any?(helper.internal.events, fn event ->
               event.type == :leave_ritual and event.target_guid == 77 and event.source_guid == 1
             end)

      refute Enum.any?(helper.internal.events, &(&1.type == :despawn_entity))
    end

    test "portal completion clears a helper channel without releasing it again" do
      visual = %Spell{id: 698, duration_ms: 120_000, attributes: MapSet.new([:channeled])}

      helper = SpellBT.start_game_object_channel(character(), 77, visual, 120_000, 1_000)
      helper = SpellBT.finish_game_object_channel(helper, 77)

      assert helper.internal.casting == nil
      assert helper.unit.channel_object == 0
      refute Enum.any?(helper.internal.events, &(&1.type in [:leave_ritual, :despawn_entity]))
    end
  end

  describe "Conflagrate" do
    test "validation requires the caster's Immolate metadata" do
      caster = character()

      spell = %Spell{
        id: 17_962,
        name: "Conflagrate",
        script_name: "spell_warlock_conflagrate",
        school: :fire,
        spell_family: 5,
        family_flags_0: 0x00000200
      }

      target_info = %{alive?: true, hostile?: true, attackable?: true, aura_sources: MapSet.new()}

      assert CastValidation.validate(caster, spell, %Targets{unit_guid: 2}, target_info, 1_000) ==
               {:error, :target_aurastate}

      target_info = %{target_info | aura_sources: MapSet.new([{348, 5, 0x00000004, 0, 1}])}
      assert CastValidation.validate(caster, spell, %Targets{unit_guid: 2}, target_info, 1_000) == :ok
    end

    test "requires and consumes the caster's Immolate" do
      immolate = %Spell{id: 348, name: "Immolate", school: :fire, spell_family: 5, family_flags_0: 0x00000004}

      target =
        mob([
          %Holder{
            spell: immolate,
            caster_guid: 1,
            auras: [%Aura{type: :periodic_damage, amount: 10}]
          }
        ])

      spell = %Spell{
        id: 17_962,
        name: "Conflagrate",
        script_name: "spell_warlock_conflagrate",
        school: :fire,
        spell_family: 5,
        family_flags_0: 0x00000200,
        effects: [%Effect{type: :school_damage, base_points: 99}]
      }

      context = %CastContext{caster_guid: 1, caster_level: 40, spell_damage_bonus: %{}}

      {result, _events} = SpellEffect.receive(target, context, spell, 1_000)

      assert result.unit.health == 101
      assert result.unit.auras == []
    end

    test "does no damage without the caster's Immolate" do
      spell = %Spell{
        id: 17_962,
        name: "Conflagrate",
        script_name: "spell_warlock_conflagrate",
        school: :fire,
        spell_family: 5,
        family_flags_0: 0x00000200,
        effects: [%Effect{type: :school_damage, base_points: 99}]
      }

      context = %CastContext{caster_guid: 1, caster_level: 40, spell_damage_bonus: %{}}

      {result, events} = SpellEffect.receive(mob(), context, spell, 1_000)

      assert result.unit.health == 200
      assert events == []
    end
  end

  describe "Curse of Agony" do
    test "ramps from half damage to normal and then one-and-a-half damage" do
      spell = %Spell{id: 980, name: "Curse of Agony", school: :shadow, spell_family: 5, family_flags_0: 0x00000400}

      early = agony_target(spell, 3_000)
      {early, _events} = AuraLogic.tick(early, 3_000)
      assert early.unit.health == 195

      late = agony_target(spell, 19_000)
      {late, _events} = AuraLogic.tick(late, 19_000)
      assert late.unit.health == 185
    end
  end

  describe "Curse of Idiocy" do
    test "periodic stacking stops after both encoded stat losses reach the VMangos cap" do
      below_cap = idiocy_target(12, 1)
      {_target, events} = AuraLogic.tick(below_cap, 2_000)
      assert Enum.any?(events, &(&1.type == :trigger_spell and &1.spell_id == 1010))

      capped = idiocy_target(13, 1)
      {_target, events} = AuraLogic.tick(capped, 2_000)
      refute Enum.any?(events, &(&1.type == :trigger_spell))
    end

    test "does not recursively trigger when self-cast" do
      target = idiocy_target(1, 2)
      {_target, events} = AuraLogic.tick(target, 2_000)
      refute Enum.any?(events, &(&1.type == :trigger_spell))
    end
  end

  describe "Curse of Weakness" do
    test "reduces the target's physical weapon damage" do
      curse = %Holder{
        spell: %Spell{id: 702},
        caster_guid: 1,
        auras: [%Aura{type: :mod_damage_done, amount: -5, misc_value: 1}]
      }

      target = mob([curse])
      target = %{target | unit: %{target.unit | min_damage: 20.0, max_damage: 30.0}}

      assert Combat.damage_range(target) == {15.0, 25.0}
    end
  end

  describe "Curse of Tongues" do
    test "negative casting speed increases cast duration" do
      spell = %Spell{id: 686, cast_time_ms: 2_000}
      cast = spell |> Cast.new(%Targets{}, 1_000) |> Cast.apply_speed_modifier(-50)

      assert cast.cast_time_ms == 4_000
      assert cast.ends_at == 5_000
    end
  end

  describe "Demonic Sacrifice" do
    test "kills the pet and triggers the demon-specific owner buff" do
      spell = %Spell{
        id: 18_788,
        name: "Demonic Sacrifice",
        script_name: "spell_warlock_demonic_sacrifice",
        effects: [%Effect{type: :instakill}]
      }

      context = %CastContext{caster_guid: 1, caster_level: 40}
      pet = mob()
      pet = %{pet | object: %Object{guid: 2, entry: 416}}

      {result, events} = SpellEffect.receive(pet, context, spell, 1_000)

      assert result.unit.health == 0
      assert Enum.any?(events, &(&1.type == :trigger_spell and &1.target_guid == 1 and &1.spell_id == 18_789))
    end
  end

  describe "Soul Link" do
    test "casts the link aura back from the pet to its owner" do
      spell = %Spell{
        id: 19_028,
        name: "Soul Link",
        effects: [%Effect{type: :dummy}],
        script_steps: [
          %ScriptStep{
            script_id: 19_028,
            command: :cast_spell,
            datalong: 18_814,
            target_type: :provided,
            swap_initial?: true
          }
        ]
      }

      context = %CastContext{caster_guid: 1, caster_level: 40, target_guid: 2}

      {_pet, events} = SpellEffect.receive(pet(), context, spell, 1_000)

      assert Enum.any?(events, fn event ->
               event.type == :trigger_spell and event.source_guid == 2 and event.target_guid == 1 and
                 event.spell_id == 18_814
             end)
    end

    test "redirects thirty percent of linked owner damage to the pet" do
      linked =
        character()
        |> then(fn character ->
          holder = %Holder{
            spell: %Spell{id: 25_228},
            caster_guid: 2,
            auras: [%Aura{type: :split_damage_percent, amount: 30, misc_value: 127}]
          }

          %{character | unit: %{character.unit | auras: [holder]}}
        end)

      assert AuraLogic.damage_redirect(linked, 100, :shadow) == {70, {2, 30}}
    end

    test "applies the pet-cast link aura to its owner" do
      spell = %Spell{
        id: 25_228,
        effects: [
          %Effect{
            type: :apply_area_aura,
            aura: :split_damage_percent,
            base_points: 30,
            misc_value: 127,
            implicit_target_a: :caster
          }
        ]
      }

      context = %CastContext{caster_guid: 2, caster_level: 40, target_role: :caster}
      {owner, _events} = SpellEffect.receive(character(), context, spell, 1_000)

      assert AuraLogic.damage_redirect(owner, 100, :shadow) == {70, {2, 30}}
    end
  end

  describe "Health Funnel" do
    test "routes the heal aura only to the pet and the caster aura only to the warlock" do
      spell = %Spell{
        id: 755,
        name: "Health Funnel",
        effects: [
          %Effect{type: :apply_aura, aura: :periodic_heal, base_points: 11, implicit_target_a: :pet},
          %Effect{type: :apply_aura, aura: :mod_health_regen_percent, base_points: -101, implicit_target_a: :caster}
        ]
      }

      caster_context = %CastContext{caster_guid: 1, caster_level: 40, target_role: :caster}
      pet_context = %CastContext{caster_guid: 1, caster_level: 40, target_role: :pet}

      {caster, _events} = SpellEffect.receive(character(), caster_context, spell, 1_000)
      {pet, _events} = SpellEffect.receive(pet(), pet_context, spell, 1_000)

      assert AuraLogic.has_aura?(caster, :mod_health_regen_percent)
      refute AuraLogic.has_aura?(caster, :periodic_heal)
      assert AuraLogic.has_aura?(pet, :periodic_heal)
      refute AuraLogic.has_aura?(pet, :mod_health_regen_percent)
    end

    test "cancelling the channel removes its aura from the remote pet" do
      spell = %Spell{
        id: 755,
        name: "Health Funnel",
        duration_ms: 10_000,
        attributes: MapSet.new([:channeled]),
        effects: [%Effect{type: :apply_aura, aura: :periodic_heal, implicit_target_a: :pet}]
      }

      caster = character(summon: 2)
      caster = SpellBT.start_cast(caster, spell, %Targets{}, 1_000)
      caster = SpellBT.clear_cast(caster)

      assert Enum.any?(caster.internal.events, fn event ->
               event.type == :remove_aura and event.source_guid == 1 and event.target_guid == 2 and
                 event.spell_id == 755
             end)
    end
  end

  describe "pet commands" do
    test "attack assigns the commanded target and enters combat" do
      pet = pet()
      result = PetBT.command(pet, :attack, 99)

      assert result.unit.target == 99
      assert result.internal.in_combat
      assert result.internal.pet.command_state == :attack
    end

    test "follow clears combat and returns ownership to follow mode" do
      pet = PetBT.command(pet(), :attack, 99)
      result = PetBT.command(pet, :follow, 0)

      assert result.unit.target == 0
      refute result.internal.in_combat
      assert result.internal.pet.command_state == :follow
    end

    test "passive immediately stops combat" do
      pet = PetBT.command(pet(), :attack, 99)
      result = PetBT.reaction(pet, :passive)

      assert result.unit.target == 0
      refute result.internal.in_combat
      assert result.internal.pet.reaction_state == :passive
    end

    test "action toggles update pet autocast state" do
      pet = pet()
      pet = %{pet | internal: %{pet.internal | spellbook: %{11_778 => %Spell{id: 11_778}}}}

      enabled = PetBT.set_actions(pet, [%{position: 3, action: 11_778, action_type: 0xC1}])
      disabled = PetBT.set_actions(enabled, [%{position: 3, action: 11_778, action_type: 0x81}])

      assert MapSet.member?(enabled.internal.pet.autocast, 11_778)
      refute MapSet.member?(disabled.internal.pet.autocast, 11_778)
    end
  end

  defp character(overrides \\ []) do
    unit = struct(%Unit{health: 100, max_health: 100, power1: 100, max_power1: 100, level: 40, auras: []}, overrides)

    %Character{
      object: %Object{guid: 1},
      unit: unit,
      player: %Player{},
      internal: %Internal{world: %WorldRef{map_id: 0}, events: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp mob(auras \\ []) do
    %Mob{
      object: %Object{guid: 2, entry: 100},
      unit: %Unit{health: 200, max_health: 200, power1: 100, max_power1: 100, level: 20, auras: auras},
      internal: %Internal{world: %WorldRef{map_id: 0}, creature: %Creature{}, events: []},
      movement_block: %MovementBlock{position: {1.0, 0.0, 0.0, 0.0}}
    }
  end

  defp pet do
    mob()
    |> then(fn mob ->
      %{mob | internal: %{mob.internal | pet: %Pet{owner_guid: 1, profile: :combat}, in_combat: false}}
    end)
  end

  defp agony_target(spell, next_tick_at) do
    holder = %Holder{
      spell: spell,
      caster_guid: 1,
      caster_level: 40,
      applied_at: 1_000,
      expires_at: 30_000,
      auras: [
        %Aura{
          type: :periodic_damage,
          amount: 10,
          amplitude_ms: 2_000,
          next_tick_at: next_tick_at
        }
      ]
    }

    mob([holder])
  end

  defp idiocy_target(stacks, caster_guid) do
    spell = %Spell{id: 1010, script_name: "spell_warlock_curse_of_idiocy", stack_amount: 15}

    holder = %Holder{
      spell: spell,
      caster_guid: caster_guid,
      caster_level: 40,
      stacks: stacks,
      applied_at: 1_000,
      expires_at: 60_000,
      auras: [
        %Aura{type: :mod_stat, amount: -7, misc_value: 3},
        %Aura{type: :mod_stat, amount: -7, misc_value: 4},
        %Aura{
          type: :periodic_trigger_spell,
          trigger_spell_id: 1010,
          amplitude_ms: 1_000,
          next_tick_at: 2_000
        }
      ]
    }

    mob([holder])
  end
end
