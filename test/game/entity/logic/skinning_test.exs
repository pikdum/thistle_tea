defmodule ThistleTea.Game.Entity.Logic.SkinningTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot, as: InternalLoot
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.Skinning
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

  setup [:skinning_fixture]

  describe "validate/4" do
    test "accepts a dead, looted creature through general cast validation", %{
      caster: caster,
      target: target,
      spell: spell
    } do
      assert :ok = CastValidation.validate(caster, spell, Target.unit(target.guid), target, 0, count_item: &knife/1)

      assert {:error, :targets_dead} =
               CastValidation.validate(caster, %Spell{id: 1}, Target.unit(target.guid), target, 0)
    end

    test "requires a trained profession and a knife without consuming it", %{
      caster: caster,
      target: target,
      spell: spell
    } do
      assert {:error, :equipped_item} = Skinning.validate(caster, spell, target, count_item: fn _ -> 0 end)
      caster = %{caster | player: %{caster.player | skills: %{}}}
      assert {:error, :low_castlevel} = Skinning.validate(caster, spell, target, count_item: &knife/1)
    end

    test "accepts the two vanilla skinning weapon alternatives", %{caster: caster, target: target, spell: spell} do
      for id <- [12_709, 19_901] do
        assert :ok = Skinning.validate(caster, spell, target, count_item: fn item -> if item == id, do: 1, else: 0 end)
      end
    end

    test "rejects living, owned, unskinnable, unlooted, and already skinned targets", %{target: target} do
      assert {:error, :target_not_dead} = Skinning.validate_target(%{target | alive?: true}, 300)
      assert {:error, :bad_targets} = Skinning.validate_target(%{target | owner_guid: 1}, 300)
      assert {:error, :bad_targets} = Skinning.validate_target(%{target | guid: 1}, 300)
      assert {:error, :target_unskinnable} = Skinning.validate_target(%{target | skinning_id: 0}, 300)
      assert {:error, :target_not_looted} = Skinning.validate_target(%{target | body_loot?: true}, 300)
      assert {:error, :target_unskinnable} = Skinning.validate_target(%{target | skinned?: true}, 300)
    end

    test "uses the vanilla low-skill and high-skill requirements", %{target: target} do
      assert :ok = Skinning.validate_target(%{target | level: 10}, 1)
      assert {:error, :low_castlevel} = Skinning.validate_target(%{target | level: 11}, 9)
      assert :ok = Skinning.validate_target(%{target | level: 11}, 10)
      assert {:error, :low_castlevel} = Skinning.validate_target(%{target | level: 20}, 99)
      assert :ok = Skinning.validate_target(%{target | level: 20}, 100)
      assert {:error, :low_castlevel} = Skinning.validate_target(%{target | level: 61}, 300)
      assert :ok = Skinning.validate_target(%{target | level: 61}, 305)
    end
  end

  describe "skill/1" do
    test "includes active skill bonuses", %{caster: caster} do
      holder = %Holder{
        spell: %Spell{id: 2},
        auras: [
          %Aura{type: :mod_skill, misc_value: 393, amount: 5},
          %Aura{type: :mod_skill, misc_value: 356, amount: 100}
        ]
      }

      assert Skinning.skill(%{caster | unit: %{caster.unit | auras: [holder]}}) == 6
    end
  end

  describe "attempt?/3" do
    test "fails difficult attempts without requiring a roll at maximum skill" do
      refute Skinning.attempt?(20, 100, 99)
      assert Skinning.attempt?(20, 100, 100)
      assert Skinning.attempt?(60, 300, 275)
    end
  end

  describe "skill_up/4" do
    test "gains one point, respects caps, and gives nothing for gray corpses", %{caster: caster} do
      assert {:gained, skills} = Skinning.skill_up(caster.player.skills, 5, 0, 0)
      assert Skills.value(skills, 393) == 2
      capped = %{393 => %{value: 75, max: 75, range: :tier, always_max?: false}}
      assert :unchanged = Skinning.skill_up(capped, 17, 0, 0)
      assert :unchanged = Skinning.skill_up(%{393 => %{value: 100, max: 150}}, 5, 0, 0)
      assert :unchanged = Skinning.skill_up(%{}, 5, 0, 0)
    end

    test "scales difficulty, elite chance, and the 75-point gathering steps" do
      assert Skinning.gain_chance(24, 5, 0) == 100
      assert Skinning.gain_chance(25, 5, 0) == 75
      assert Skinning.gain_chance(50, 5, 0) == 25
      assert Skinning.gain_chance(75, 17, 0) == 50
      assert Skinning.gain_chance(75, 17, 1) == 100
      assert Skinning.gain_chance(150, 30, 0) == 25
      assert Skinning.gain_chance(225, 45, 0) == 12.5
    end
  end

  describe "sync/1" do
    test "projects readiness only after body loot is gone and resets on respawn", %{target: target} do
      mob = %Mob{
        object: %Object{guid: target.guid},
        unit: %Unit{health: 0, max_health: 10, level: 5, flags: 8},
        internal: %Internal{loot: %InternalLoot{skinning_id: 1}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      assert Skinning.sync(mob).unit.flags == (8 ||| 0x04000000)
      with_loot = put_in(mob.internal.loot.session, LootSession.new(%Loot{gold: 1}, nil))
      assert Skinning.sync(with_loot).unit.flags == 8
      skinned = put_in(mob.internal.loot.skinned?, true)
      assert Skinning.sync(skinned).unit.flags == 8
      respawned = mob |> Skinning.sync() |> Mob.respawn()
      assert respawned.unit.flags == 8
      refute respawned.internal.loot.skinned?
    end
  end

  describe "Casting.advance/2" do
    test "queues one owner-local skinning request at impact", %{caster: caster, target: target, spell: spell} do
      resolution = %CastResolution{
        hits: [target.guid],
        misses: [],
        impacts: [],
        costs: %Costs{
          power: %PowerCost{power_type: nil, amount: 0},
          channel_power: %PowerCost{power_type: nil, amount: 0},
          reagents: [],
          cast_item_guid: nil,
          modifier_holder_ids: []
        },
        followups: %Followups{
          packet_hits: [target.guid],
          selected_unit_guid: target.guid,
          object_guid: nil,
          item_guid: nil,
          ground_position: nil,
          area_position: nil
        }
      }

      cast = %{Cast.new(spell, Target.unit(target.guid), 0) | phase: :launch, resolution: resolution}
      caster = %{caster | internal: %{caster.internal | casting: cast}}
      assert {:finished, caster} = Casting.advance(caster, 3_000)

      assert [%Effects.SkinCorpse{target_guid: guid, spell_id: 8613}] =
               Enum.filter(caster.internal.events, &is_struct(&1, Effects.SkinCorpse))

      assert guid == target.guid
      assert {:idle, _} = Casting.advance(caster, 4_000)
    end
  end

  defp knife(7005), do: 1
  defp knife(_), do: 0

  defp skinning_fixture(_) do
    caster = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, level: 50, auras: []},
      player: %Player{skills: Skills.learn_rank(%{}, 393, 75)},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    target = %{
      guid: Guid.from_low_guid(:mob, 299, 1),
      alive?: false,
      owner_guid: nil,
      level: 5,
      skinning_id: 1,
      body_loot?: false,
      skinned?: false
    }

    spell = %Spell{
      id: 8613,
      effects: [%Effect{index: 0, type: :skinning, implicit_target_a: :any_unit}],
      cast_time_ms: 3_000
    }

    %{caster: caster, target: target, spell: spell}
  end
end
