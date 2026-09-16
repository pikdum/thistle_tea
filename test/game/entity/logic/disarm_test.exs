defmodule ThistleTea.Game.Entity.Logic.DisarmTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Disarm
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  setup [:character]

  defp character(_) do
    unit =
      %Unit{
        class: 1,
        level: 50,
        health: 1_000,
        max_health: 1_000,
        base_min_damage: 40.0,
        base_max_damage: 60.0,
        base_melee_attack_time: 3_000,
        base_offhand_min_damage: 20.0,
        base_offhand_max_damage: 30.0,
        offhand_attack_time: 1_500,
        attack_power: 140,
        auras: []
      }
      |> Stats.recompute()

    character = %Character{
      object: %Object{guid: 1},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      unit: unit,
      player: %Player{skills: %{162 => %{value: 37}}},
      internal: %Internal{}
    }

    %{character: character}
  end

  defp holder(id \\ 676) do
    %Holder{
      spell: %Spell{id: id},
      caster_guid: 2,
      expires_at: 10_000,
      negative?: true,
      auras: [%Aura{type: :mod_disarm}]
    }
  end

  defp disarm(character, holders \\ [holder()]) do
    {character, _events} = AuraLogic.transition(character, %Change{holders: holders, cause: :applied, now: 0})
    character
  end

  describe "damage_range/1" do
    test "restores weapon damage when death removes disarm", %{character: character} do
      character = character |> disarm() |> Core.take_damage(1_000, 500)
      assert character.unit.health == 0
      refute Disarm.active?(character)
      assert Combat.damage_range(character) == {70.0, 90.0}
      assert Combat.attack_speed_ms(character) == 3_000
    end

    test "uses unarmed damage plus attack power while preserving offhand damage", %{character: character} do
      assert Combat.damage_range(character) == {70.0, 90.0}
      offhand = Combat.offhand_damage_range(character)
      character = disarm(character)
      assert Combat.damage_range(character) == {21.0, 22.0}
      assert Combat.attack_speed_ms(character) == 2_000
      assert Combat.offhand_damage_range(character) == offhand
      assert Combat.offhand_attack_speed_ms(character) == 1_500
      assert character.unit.base_min_damage == 40.0
      assert character.unit.base_melee_attack_time == 3_000
      assert Stats.recompute(character.unit) == character.unit
    end

    test "updates attack power while disarmed and restores current weapon inputs", %{character: character} do
      character = disarm(character)

      unit =
        Stats.recompute(%{
          character.unit
          | attack_power: 280,
            base_min_damage: 90.0,
            base_max_damage: 100.0,
            base_melee_attack_time: 3_500
        })

      assert {unit.min_damage, unit.max_damage} == {41.0, 42.0}
      {restored, _events} = AuraLogic.remove_spells(%{character | unit: unit}, [676], 1_000)
      assert Combat.damage_range(restored) == {160.0, 170.0}
      assert Combat.attack_speed_ms(restored) == 3_500
      refute Disarm.active?(restored)
    end

    test "keeps disarm until the final overlapping aura expires", %{character: character} do
      character = disarm(character, [holder(), %{holder(677) | expires_at: 20_000}])
      {character, _events} = AuraLogic.expire_due(character, 10_000)
      assert Disarm.active?(character)
      assert Combat.damage_range(character) == {21.0, 22.0}
      {character, _events} = AuraLogic.expire_due(character, 20_000)
      refute Disarm.active?(character)
      assert Combat.damage_range(character) == {70.0, 90.0}
      assert Combat.attack_speed_ms(character) == 3_000
      assert Bitwise.band(character.unit.flags, 0x00200000) == 0
    end

    test "preserves feral damage and rechecks disarm when leaving form", %{character: character} do
      unit = %{character.unit | class: 11, shapeshift_form: 1} |> Stats.recompute()
      expected = {unit.min_damage, unit.max_damage, unit.base_attack_time}
      unit = Stats.recompute(%{unit | auras: [holder()]})
      assert {unit.min_damage, unit.max_damage, unit.base_attack_time} == expected
      unit = Stats.recompute(%{unit | shapeshift_form: 0})
      assert {unit.min_damage, unit.max_damage, unit.base_attack_time} == {21.0, 22.0, 2_000}
    end

    test "reduces armed creature mainhand damage without changing its speed or offhand" do
      unit = %Unit{
        min_damage: 100.0,
        max_damage: 150.0,
        base_attack_time: 2_600,
        min_offhand_damage: 30.0,
        max_offhand_damage: 40.0,
        auras: [holder()],
        virtual_item_info: <<2, 0::184>>
      }

      mob = %Mob{unit: unit}
      assert Combat.damage_range(mob) == {40.0, 60.0}
      assert Combat.attack_speed_ms(mob) == 2_600
      assert Combat.offhand_damage_range(mob) == {15.0, 20.0}
      assert Combat.damage_range(%{mob | unit: %{unit | virtual_item_info: <<0::192>>}}) == {100.0, 150.0}
    end
  end

  describe "validate/2" do
    test "rejects melee weapons but permits ranged attacks and weaponless abilities", %{character: character} do
      spell = %Spell{id: 78, equipped_item_class: 2, dmg_class: 2}
      assert Disarm.validate(character, spell) == :ok
      character = disarm(character)
      assert Disarm.validate(character, spell) == {:error, :equipped_item}
      assert Disarm.validate(character, %{spell | dmg_class: 3}) == :ok
      assert Disarm.validate(character, %{spell | dmg_class: 1, equipped_item_subclass_mask: 0x80000}) == :ok
      assert Disarm.validate(character, %{spell | equipped_item_class: -1}) == :ok
      assert Disarm.validate(character, %{spell | equipped_item_class: 4}) == :ok
      assert CastValidation.validate(character, spell, Target.self(1), nil, 0) == {:error, :equipped_item}
    end

    test "blocks weapon damage abilities only on armed creatures" do
      mob = %Mob{unit: %Unit{auras: [holder()], virtual_item_info: <<2, 0::184>>}}
      spell = %Spell{id: 1, effects: [%Effect{type: :weapon_damage}]}
      assert Disarm.validate(mob, spell) == {:error, :equipped_item}
      assert Disarm.validate(mob, %{spell | effects: [%Effect{type: :school_damage}]}) == :ok
      assert Disarm.validate(%{mob | unit: %{mob.unit | virtual_item_info: nil}}, spell) == :ok
    end
  end

  describe "parry_disabled?/1" do
    test "requires a remaining offhand weapon to parry while disarmed", %{character: character} do
      character = disarm(character)
      refute Disarm.parry_disabled?(character)
      character = %{character | unit: %{character.unit | base_offhand_max_damage: nil}}
      assert Disarm.parry_disabled?(character)
      synced = CombatRatings.sync(character)
      assert synced.player.parry_percentage == 0.0
      attack = %{caster_level: 50, caster_player?: true, caster_attack_skill: 250}
      refute AttackTable.resolve(character, attack, 100, roll: 700).outcome == :parry
      {character, _events} = AuraLogic.remove_spells(character, [676], 1_000)
      assert character.player.parry_percentage == 5.0
      assert AttackTable.resolve(character, attack, 100, roll: 700).outcome == :parry
    end
  end

  describe "start/5" do
    test "rejects weapon abilities before queueing or spending resources", %{character: character} do
      spell = %Spell{id: 78, equipped_item_class: 2, attributes: MapSet.new([:on_next_swing])}
      character = character |> disarm() |> Casting.start(spell, Target.unit(2), 0)
      assert character.internal.next_swing_spell == nil
      assert character.internal.casting == nil
      assert [%Effects.SpellCastFailed{reason: :equipped_item}] = character.internal.events
    end
  end

  describe "complete/2" do
    test "rejects a weapon cast disarmed during preparation", %{character: character} do
      spell = %Spell{id: 1464, equipped_item_class: 2, cast_time_ms: 1_500}
      cast = Cast.new(spell, Target.unit(2), 0)
      character = disarm(%{character | internal: %{character.internal | casting: cast}})
      character = Casting.complete(character, 1_500)
      assert character.internal.casting == nil
      assert [%Effects.SpellCastFailed{reason: :equipped_item}] = character.internal.events
    end
  end

  describe "from_caster/3" do
    test "snapshots unarmed damage and skill for allowed melee abilities", %{character: character} do
      spell = %Spell{id: 1, school: :physical, dmg_class: 2}
      context = CastContext.from_caster(disarm(character), spell, 2)
      assert context.weapon_base_min == 1.0
      assert context.weapon_base_max == 2.0
      assert context.attack_power == 140
      assert context.attack_skill == 37
      assert context.attack_time_ms == 2_000
      assert context.normalized_speed == 2.0
    end
  end
end
