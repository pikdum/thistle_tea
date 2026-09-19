defmodule ThistleTea.Game.Entity.Logic.PetHappinessTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Regen
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Entity.Logic.AI.TickPlan
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PetHappiness
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.SpellEffect.DamageHeal
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:build_pet]

  describe "change/2" do
    test "scales flat melee buffs along with the pet's weapon damage", %{pet: pet} do
      effect = %Effect{index: 0, type: :apply_aura, aura: :mod_damage_done, base_points: 20, misc_value: 1}
      spell = %Spell{id: 1, duration_ms: 5_000, effects: [effect]}
      {pet, _events} = Aura.apply_spell(pet, 10, 50, spell, 0)
      assert Combat.damage_range(pet) == {75.0, 105.0}
      assert Combat.damage_range(PetHappiness.change(pet, 500_000)) == {125.0, 175.0}
    end

    test "crosses exact happiness thresholds and derives damage without compounding", %{pet: pet} do
      for {happiness, multiplier} <- [{0, 0.75}, {332_999, 0.75}, {333_000, 1.0}, {665_999, 1.0}, {666_000, 1.25}] do
        changed = PetHappiness.change(pet, happiness - pet.unit.power5)
        assert PetHappiness.damage_multiplier(changed) == multiplier
        assert Combat.damage_range(changed) == {80 * multiplier, 120 * multiplier}
        assert changed.unit.base_min_damage == 80
        assert Stats.recompute(changed.unit) == changed.unit
      end
    end

    test "feeding and drains clamp to resource bounds", %{pet: pet} do
      happy = Resources.gain_power(pet, 4, 2_000_000)
      assert happy.unit.power5 == 1_050_000
      assert happy.unit.min_damage == 100
      unhappy = PetHappiness.change(happy, -2_000_000)
      assert unhappy.unit.power5 == 0
      assert unhappy.unit.min_damage == 60
      assert unhappy.internal.broadcast_update?
    end

    test "ignores summoned demons and ordinary creatures", %{pet: pet} do
      for kind <- [:summon, :charmed] do
        other = %{pet | internal: %{pet.internal | pet: %{pet.internal.pet | kind: kind}}}
        assert PetHappiness.change(other, 500_000) == other
        assert PetHappiness.tick(other, 100_000) == other
      end

      assert PetHappiness.damage_multiplier(%Unit{power5: 0, max_power5: 0}) == 1.0
    end

    test "new canonical weapon inputs survive happiness changes", %{pet: pet} do
      pet = %{pet | unit: %{pet.unit | base_min_damage: 160, base_max_damage: 240}}
      happy = PetHappiness.change(pet, 666_000)
      assert {happy.unit.min_damage, happy.unit.max_damage} == {200.0, 300.0}
    end
  end

  describe "tick/2" do
    test "starts a full interval and decays once per due tick", %{pet: pet} do
      pet = PetHappiness.tick(pet, 1_000)
      assert pet.unit.power5 == 166_500
      assert PetHappiness.next_tick_at(pet) == 8_500
      assert PetHappiness.tick(pet, 8_499) == pet
      decayed = PetHappiness.tick(pet, 8_500)
      assert decayed.unit.power5 == 157_750
      assert PetHappiness.next_tick_at(decayed) == 16_000
      assert PetHappiness.tick(decayed, 8_500) == decayed
      late = PetHappiness.tick(decayed, 100_000)
      assert late.unit.power5 == 149_000
      assert PetHappiness.next_tick_at(late) == 107_500
    end

    test "uses loyalty and the reference combat multiplier", %{pet: pet} do
      for {loyalty, loss} <- [{1, 8_750}, {2, 4_375}, {3, 2_125}, {4, 1_000}, {5, 500}, {6, 250}],
          combat? <- [false, true] do
        pet = %{pet | unit: %{pet.unit | pet_loyalty: loyalty}, internal: %{pet.internal | in_combat: combat?}}
        pet = pet |> PetHappiness.tick(0) |> PetHappiness.tick(7_500)
        assert pet.unit.power5 == 166_500 - if(combat?, do: trunc(loss * 1.5), else: loss)
      end
    end

    test "maintenance and the tick plan retain the independent happiness deadline", %{pet: pet} do
      assert {:failure, pet, blackboard} = Regen.tick(pet, Blackboard.new(), 0)
      pet = %{pet | internal: %{pet.internal | blackboard: blackboard}}
      assert %TickPlan.Wake{at: 7_500, source: :pet_happiness} = Tick.plan(pet, :success, 0) |> TickPlan.next()
      assert {:failure, pet, _} = Regen.tick(pet, blackboard, 7_500)
      assert pet.unit.power5 == 157_750
    end

    test "does not decay a corpse", %{pet: pet} do
      dead = %{pet | unit: %{pet.unit | health: 0}}
      assert PetHappiness.tick(dead, 100_000) == dead
      assert PetHappiness.next_tick_at(dead) == nil
    end
  end

  describe "on_death/2" do
    test "loses one tier and clears the deadline outside battlegrounds", %{pet: pet} do
      pet = pet |> PetHappiness.change(500_000) |> PetHappiness.tick(0)
      dead = PetHappiness.on_death(pet, false)
      assert dead.unit.power5 == 333_500
      assert dead.internal.pet.next_happiness_at == nil
      assert dead.unit.min_damage == 80
      assert Enum.any?(dead.internal.events, &match?(%Effects.PetDied{source_guid: 1, target_guid: 10}, &1))
      assert PetHappiness.on_death(pet, true).unit.power5 == pet.unit.power5
      assert PetHappiness.on_death(%{pet | unit: %{pet.unit | power5: 100}}, false).unit.power5 == 0
    end
  end

  describe "from_caster/3" do
    test "snapshots happiness for both melee and magic abilities", %{pet: pet} do
      for damage_class <- [1, 2] do
        spell = %Spell{id: 1, school: :nature, dmg_class: damage_class}
        context = CastContext.from_caster(pet, spell, 2)
        assert context.happiness_multiplier == 0.75
        happy = PetHappiness.change(pet, 500_000)
        assert CastContext.from_caster(happy, spell, 2).happiness_multiplier == 1.25
        assert context.happiness_multiplier == 0.75
      end
    end

    test "changes actual direct damage for physical and magical pet abilities", %{pet: pet} do
      target = %{pet | object: %Object{guid: 2}, internal: %{pet.internal | pet: nil}}

      for {happiness, damage} <- [{0, 60}, {333_000, 80}, {666_000, 100}],
          {school, dmg_class} <- [{:physical, 2}, {:nature, 1}] do
        caster = PetHappiness.change(pet, happiness - pet.unit.power5)
        effect = %Effect{type: :school_damage, base_points: 80, implicit_target_a: :target_enemy}
        spell = %Spell{id: 1, school: school, dmg_class: dmg_class, effects: [effect]}
        context = %{CastContext.from_caster(caster, spell, 2) | spell_crit_chance: 0, melee_crit?: false}
        {damaged, events} = DamageHeal.apply(target, context, spell, effect, 0)
        assert damaged.unit.health == 1_000 - damage
        assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: ^damage}, &1))
      end
    end

    test "snapshots periodic damage without multiplying healing or feeding", %{pet: pet} do
      caster = PetHappiness.change(pet, 500_000)

      for {type, amount} <- [{:periodic_damage, 100}, {:periodic_heal, 80}, {:periodic_energize, 80}] do
        effect = %Effect{index: 0, type: :apply_aura, aura: type, base_points: 80, amplitude_ms: 1_000, misc_value: 4}
        spell = %Spell{id: 1, school: :nature, duration_ms: 5_000, effects: [effect]}
        context = CastContext.from_caster(caster, spell, pet.object.guid)
        {target, _events} = Aura.apply_spell(pet, context, spell, 0)
        assert hd(hd(target.unit.auras).auras).amount == amount
      end
    end
  end

  defp build_pet(_context) do
    pet = %Mob{
      object: %Object{guid: 1},
      unit:
        Stats.recompute(%Unit{
          level: 50,
          health: 1_000,
          max_health: 1_000,
          power_type: 2,
          power3: 100,
          max_power3: 100,
          power5: 166_500,
          max_power5: 1_050_000,
          pet_loyalty: 1,
          base_min_damage: 80,
          base_max_damage: 120,
          base_attack_time: 2_000,
          auras: []
        }),
      internal: %Internal{
        pet: %Pet{kind: :hunter, owner_guid: 10},
        creature: %Creature{regenerate_stats: 3, damage_multiplier: 1.0},
        world: WorldRef.open(0)
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{pet: pet}
  end
end
