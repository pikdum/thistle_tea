defmodule ThistleTea.Game.Entity.Logic.CombatSkillsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.CombatSkills
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:combatants]

  describe "snapshot/3" do
    test "combines both aura bonuses with the skill for each hand", %{character: character} do
      character = with_auras(character, [bonus(:mod_skill, 43, 3), bonus(:mod_skill_talent, 43, 5)])
      mainhand = CombatSkills.snapshot(character, :mainhand, &template/1)
      offhand = CombatSkills.snapshot(character, :offhand, &template/1)
      ranged = CombatSkills.snapshot(character, :ranged, &template/1)

      assert mainhand == %{caster_attack_skill: 9, weapon_skill_id: 43}
      assert offhand == %{caster_attack_skill: 1, weapon_skill_id: 173}
      assert ranged == %{caster_attack_skill: 1, weapon_skill_id: 45}
      assert character.player.skills[43].value == 1
    end

    test "disarm trains unarmed while preserving the offhand", %{character: character} do
      character = with_auras(character, [%Aura{type: :mod_disarm}])
      assert CombatSkills.snapshot(character, :mainhand, &template/1).weapon_skill_id == 162
      assert CombatSkills.snapshot(character, :offhand, &template/1).weapon_skill_id == 173
    end

    test "natural weapons use level skill without training equipped weapons", %{character: character} do
      for form <- [1, 2, 3, 4, 5, 8] do
        shifted = %{character | unit: %{character.unit | shapeshift_form: form}}

        assert CombatSkills.snapshot(shifted, :mainhand, &template/1) == %{
                 caster_attack_skill: 300,
                 weapon_skill_id: nil
               }
      end
    end

    test "stances, stealth, shadowform and moonkin can train weapons", %{character: character} do
      for form <- [0, 17, 18, 19, 28, 30, 31] do
        shifted = %{character | unit: %{character.unit | shapeshift_form: form}}
        assert CombatSkills.snapshot(shifted, :mainhand, &template/1).weapon_skill_id == 43
      end

      wolf = %{character | unit: %{character.unit | shapeshift_form: 16}}
      assert CombatSkills.snapshot(wolf, :mainhand, &template/1).weapon_skill_id == nil
    end

    test "fishing poles and empty offhand or ranged slots cannot train", %{character: character} do
      character = %{
        character
        | player: %{character.player | visible_item_16_0: 4, visible_item_17_0: 0, visible_item_18_0: 0}
      }

      assert CombatSkills.snapshot(character, :mainhand, &template/1).weapon_skill_id == nil

      for hand <- [:offhand, :ranged] do
        assert CombatSkills.snapshot(character, hand, &template/1) == %{caster_attack_skill: 0, weapon_skill_id: nil}
      end
    end

    test "zero effective skill is retained by the attack table", %{character: character, mob: mob} do
      character = with_auras(character, [bonus(:mod_skill, 43, -10)])
      snapshot = CombatSkills.snapshot(character, :mainhand, &template/1)
      assert snapshot.caster_attack_skill == 0
      attack = Map.merge(snapshot, %{caster_level: 60, caster_player?: true, hit_chance_bonus: 0})
      assert AttackTable.roll_special(mob, attack, roll: 1_000).outcome == :miss
      refute AttackTable.roll_special(mob, %{attack | caster_attack_skill: 300}, roll: 1_000).outcome == :miss
    end
  end

  describe "resolve/4" do
    test "valid outcomes offer training once and excluded outcomes never do", %{mob: mob} do
      attack = %{caster: 5, caster_player?: true, caster_level: 60, weapon_skill_id: 173}

      for outcome <- [:normal, :crit, :glancing, :crushing, :miss, :dodge, :parry, :block, :resist] do
        assert {^mob, [%Effects.AdvanceCombatSkill{target_guid: 5, skill_id: 173}]} =
                 CombatSkills.resolve(mob, attack, outcome)
      end

      for outcome <- [:immune, :evade, :reflect] do
        assert CombatSkills.resolve(mob, attack, outcome) == {mob, []}
      end

      assert CombatSkills.resolve(mob, Map.put(attack, :skill_training?, false), :normal) == {mob, []}
    end

    test "players and player pets grant no attack or defense gains", %{character: character, mob: mob} do
      attack = %{caster: 5, caster_player?: true, caster_level: 60, weapon_skill_id: 43}
      assert CombatSkills.resolve(character, attack, :normal) == {character, []}
      pet = %{mob | internal: %{mob.internal | pet: %Pet{owner_guid: 5}}}
      assert CombatSkills.resolve(pet, attack, :normal) == {pet, []}
      attack = %{attack | caster: mob.object.guid, caster_player?: false} |> Map.put(:caster_owner_guid, 5)
      assert CombatSkills.resolve(character, attack, :normal, roll: fn _ -> true end) == {character, []}
    end

    test "defense advances on valid NPC attacks and republishes avoidance", %{character: character, mob: mob} do
      attack = %{caster: mob.object.guid, caster_player?: false, caster_level: 60}
      assert {trained, []} = CombatSkills.resolve(character, attack, :parry, roll: fn _ -> true end)
      assert trained.player.skills[95].value == 2
      assert trained.internal.broadcast_update?
      assert is_number(trained.player.dodge_percentage)
      assert CombatSkills.resolve(character, attack, :immune, roll: fn _ -> true end) == {character, []}
    end
  end

  describe "advance/3" do
    test "advances the launch skill even after a weapon swap and caps base progress", %{character: character} do
      snapshot = CombatSkills.snapshot(character, :offhand, &template/1)
      character = %{character | player: %{character.player | visible_item_17_0: 1}}
      trained = CombatSkills.advance(character, snapshot.weapon_skill_id, roll: fn _ -> true end)
      assert trained.player.skills[173].value == 2
      assert trained.player.skills[43].value == 1
      capped = %{trained | player: %{trained.player | skills: Skills.max_out(trained.player.skills)}}
      assert CombatSkills.advance(capped, 173, roll: fn _ -> true end) == capped
    end
  end

  describe "combat delivery" do
    test "the killing blow can train but late attacks on the corpse cannot", %{mob: mob} do
      attack = %{
        caster: 5,
        caster_player?: true,
        caster_level: 60,
        caster_attack_skill: 300,
        weapon_skill_id: 43,
        damage: 1_000
      }

      {corpse, events} = Combat.receive_attack(mob, attack, 1_000, roll: 9_999)
      assert corpse.unit.health == 0
      assert Enum.any?(events, &is_struct(&1, Effects.AdvanceCombatSkill))
      {_corpse, events} = Combat.receive_attack(corpse, attack, 1_001, roll: 9_999)
      refute Enum.any?(events, &is_struct(&1, Effects.AdvanceCombatSkill))
    end

    test "white swings resolve a single training message at the defender", %{mob: mob} do
      attack = %{
        caster: 5,
        caster_player?: true,
        caster_level: 60,
        caster_attack_skill: 300,
        weapon_skill_id: 173,
        damage: 1
      }

      {_mob, events} = Combat.receive_attack(mob, attack, 1_000, roll: 9_999)

      assert [%Effects.AdvanceCombatSkill{target_guid: 5, skill_id: 173}] =
               Enum.filter(events, &is_struct(&1, Effects.AdvanceCombatSkill))
    end

    test "melee and ranged weapon abilities train once, non-weapon abilities do not", %{mob: mob} do
      for {class, skill_id} <- [{2, 43}, {3, 45}] do
        spell = %Spell{
          id: 900_001,
          dmg_class: class,
          school: :physical,
          equipped_item_class: 2,
          effects: [%Effect{type: :weapon_damage, base_points: 1}]
        }

        context = %CastContext{
          caster_guid: 5,
          caster_type: :player,
          caster_level: 60,
          attack_skill: 300,
          weapon_skill_id: skill_id,
          weapon_base_min: 1,
          weapon_base_max: 1,
          hit_chance_bonus: 100
        }

        {_target, events} = SpellEffect.receive(mob, context, spell, 1_000)

        assert [%Effects.AdvanceCombatSkill{skill_id: ^skill_id}] =
                 Enum.filter(events, &is_struct(&1, Effects.AdvanceCombatSkill))

        {_target, events} = SpellEffect.receive(mob, context, %{spell | equipped_item_class: -1}, 1_000)
        refute Enum.any?(events, &is_struct(&1, Effects.AdvanceCombatSkill))
        {_target, events} = SpellEffect.receive(mob, %{context | hit_outcome: :resist}, spell, 1_000)

        assert [%Effects.AdvanceCombatSkill{skill_id: ^skill_id}] =
                 Enum.filter(events, &is_struct(&1, Effects.AdvanceCombatSkill))
      end
    end

    test "spell-damage shots and ranged debuffs train once unless immune or already dead", %{mob: mob} do
      context = %CastContext{caster_guid: 5, caster_type: :player, caster_level: 60, weapon_skill_id: 45}

      for effects <- [
            [%Effect{type: :school_damage, base_points: 500}, %Effect{type: :school_damage, base_points: 500}],
            [%Effect{type: :apply_aura, aura: :mod_decrease_speed, base_points: -50, implicit_target_a: :target_enemy}]
          ] do
        spell = %Spell{
          id: 900_003,
          dmg_class: 3,
          equipped_item_class: 2,
          school: :arcane,
          duration_ms: 10_000,
          effects: effects
        }

        {_target, events} = SpellEffect.receive(mob, context, spell, 1_000)

        assert [%Effects.AdvanceCombatSkill{skill_id: 45}] =
                 Enum.filter(events, &is_struct(&1, Effects.AdvanceCombatSkill))

        immune = with_auras(mob, [%Aura{type: :school_immunity, misc_value: 64}])
        dead = %{mob | unit: %{mob.unit | health: 0}}

        for target <- [immune, dead] do
          {_target, events} = SpellEffect.receive(target, context, spell, 1_000)
          refute Enum.any?(events, &is_struct(&1, Effects.AdvanceCombatSkill))
        end
      end
    end

    test "ranged spell damage uses weapon accuracy and trains on misses", %{mob: mob} do
      spell = %Spell{
        id: 3044,
        dmg_class: 3,
        equipped_item_class: 2,
        school: :arcane,
        effects: [%Effect{type: :school_damage, base_points: 10}]
      }

      context = %CastContext{
        caster_guid: 5,
        caster_type: :player,
        caster_level: 60,
        attack_skill: 1,
        weapon_skill_id: 45,
        hit_chance_bonus: -100
      }

      :rand.seed(:exsss, {1, 2, 3})
      results = for _ <- 1..30, do: SpellEffect.receive(mob, context, spell, 1_000)

      assert Enum.any?(results, fn {target, events} ->
               target == mob and Enum.any?(events, &match?(%Effects.SpellLogMiss{reason: :miss}, &1))
             end)

      assert Enum.any?(results, fn {target, _events} -> target.unit.health < mob.unit.health end)

      for {_target, events} <- results do
        assert [%Effects.AdvanceCombatSkill{skill_id: 45}] =
                 Enum.filter(events, &is_struct(&1, Effects.AdvanceCombatSkill))
      end
    end

    test "typed feedback reaches the registered player owner and publishes progress", %{character: character, mob: mob} do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive]) + 10_000_000)
      Entity.register(guid)
      character = %{character | object: %{character.object | guid: guid}}
      effect = %Effects.AdvanceCombatSkill{target_guid: guid, skill_id: 173}
      EventSink.emit(mob, effect)
      assert_receive {:"$gen_cast", {:advance_combat_skill, 173} = message}
      state = %State{guid: guid, character: character, connection_pid: self()}
      assert {:noreply, state, {:continue, :maybe_broadcast_update}} = PlayerServer.handle_cast(message, state)
      assert state.character.player.skills[173].value == 2
      assert state.character.internal.broadcast_update?
    end
  end

  defp combatants(_context) do
    character = %Character{
      object: %Object{guid: 5},
      unit: %Unit{level: 60, class: 1, health: 100, max_health: 100, auras: []},
      player: %Player{
        visible_item_16_0: 1,
        visible_item_17_0: 2,
        visible_item_18_0: 3,
        skills: Map.new([43, 173, 45, 162, 95], &{&1, Skills.new_entry(:level, false, 60)})
      },
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    mob = %Mob{
      object: %Object{guid: Guid.from_low_guid(:unit, 1, 901)},
      unit: %Unit{level: 60, health: 100, max_health: 100, auras: []},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {1.0, 0.0, 0.0, 0.0}}
    }

    %{character: character, mob: mob}
  end

  defp template(1), do: %{class: 2, subclass: 7}
  defp template(2), do: %{class: 2, subclass: 15}
  defp template(3), do: %{class: 2, subclass: 2}
  defp template(4), do: %{class: 2, subclass: 20}

  defp bonus(type, skill, amount), do: %Aura{type: type, misc_value: skill, amount: amount}

  defp with_auras(character, auras) do
    holder = %Holder{spell: %Spell{id: 900_002}, caster_guid: character.object.guid, auras: auras}
    %{character | unit: %{character.unit | auras: [holder]}}
  end
end
