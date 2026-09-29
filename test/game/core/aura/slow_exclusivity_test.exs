defmodule ThistleTea.Game.Core.Aura.SlowExclusivityTest do
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
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.WorldRef

  setup [:character]

  describe "apply_spell/5" do
    test "a stronger cross-caster snare replaces the weaker holder and expiry restores speed", %{character: c} do
      weak = slow(1, -40, 20_000)
      strong = slow(2, -70, 5000)
      {c, _events} = Aura.apply_spell(c, 2, 60, weak, 0)
      assert_in_delta c.movement_block.run_speed, 4.2, 0.001
      {c, events} = Aura.apply_spell(c, 3, 60, strong, 1000)
      assert ids(c) == [2]
      assert hd(c.unit.auras).caster_guid == 3
      assert_in_delta c.movement_block.run_speed, 2.1, 0.001
      assert Enum.any?(events, &match?(%Effects.MovementSpeedChanged{movement_type: :run_speed}, &1))
      {c, _events} = Aura.expire_due(c, 6000)
      assert ids(c) == []
      assert c.movement_block.run_speed == 7.0
    end

    test "weaker slows cannot refresh or replace an existing stronger snare", %{character: c} do
      {c, _events} = Aura.apply_spell(c, 2, 60, slow(1, -70, 5000), 0)
      {unchanged, events} = Aura.apply_spell(c, 3, 60, slow(2, -40, 20_000), 4900)
      assert unchanged == c
      assert events == []
    end

    test "equal strength compares full spell durations rather than remaining lifetime", %{character: c} do
      long = slow(1, -50, 20_000)
      short = slow(2, -50, 4000)
      {c, _events} = Aura.apply_spell(c, 2, 60, long, 0)
      assert {^c, []} = Aura.apply_spell(c, 3, 60, short, 19_000)
      {c, _events} = Aura.apply_spell(c, 3, 60, slow(3, -50, 20_000), 19_000)
      assert ids(c) == [3]
      assert hd(c.unit.auras).expires_at == 39_000
    end

    test "equal strength allows a longer replacement and repeated application refreshes", %{character: c} do
      long = slow(2, -50, 20_000)
      {c, _events} = Aura.apply_spell(c, 2, 60, slow(1, -50, 4000), 0)
      {c, _events} = Aura.apply_spell(c, 3, 60, long, 1000)
      {c, _events} = Aura.apply_spell(c, 3, 60, long, 2000)
      assert ids(c) == [2]
      assert hd(c.unit.auras).expires_at == 22_000
    end

    test "attack-speed penalties replace across effects slots without affecting movement", %{character: c} do
      weak = slow(1, -10, 30_000, :negative_haste)
      strong = slow(2, -20, 10_000, :negative_haste)
      strong = %{strong | effects: Enum.map(strong.effects, &%{&1 | index: 1})}
      {c, _events} = Aura.apply_spell(c, 2, 60, weak, 0)
      assert c.unit.base_attack_time == 2200
      {c, _events} = Aura.apply_spell(c, 3, 60, strong, 1000)
      assert ids(c) == [2]
      assert c.unit.base_attack_time == 2400
      assert c.unit.offhand_attack_time == 1800
      assert c.movement_block.run_speed == 7.0
      assert {^c, []} = Aura.apply_spell(c, 2, 60, weak, 2000)
      {c, _events} = Aura.expire_due(c, 11_000)
      assert c.unit.base_attack_time == 2000
      assert c.unit.offhand_attack_time == 1500
    end

    test "daze coexists and resumes after exclusive snare removal", %{character: c} do
      daze = %{slow(1, -50, 30_000) | exclusive_category: nil}
      {c, _events} = Aura.apply_spell(c, 2, 60, daze, 0)
      {c, _events} = Aura.apply_spell(c, 3, 60, slow(2, -70, 5000), 1000)
      assert ids(c) == [1, 2]
      {c, _events} = Aura.expire_due(c, 6000)
      assert ids(c) == [1]
      assert c.movement_block.run_speed == 3.5
    end

    test "death clears the remaining exclusive slow without restoring its predecessor", %{character: c} do
      {c, _events} = Aura.apply_spell(c, 2, 60, slow(1, -40, 30_000), 0)
      {c, _events} = Aura.apply_spell(c, 3, 60, slow(2, -70, 20_000), 1000)
      dead = Entity.take_damage(c, 1000, 2000)
      assert ids(dead) == []
      assert dead.movement_block.run_speed == 7.0
    end
  end

  describe "receive/4" do
    test "rejecting a weaker snare still applies the spell's direct damage", %{character: c} do
      {c, _events} = Aura.apply_spell(c, 2, 60, slow(1, -70, 20_000), 0)
      frostbolt = slow(2, -40, 5000)
      damage = %Effect{index: 1, type: :school_damage, base_points: 50, implicit_target_a: :target_enemy}
      frostbolt = %{frostbolt | effects: frostbolt.effects ++ [damage]}
      context = %CastContext{caster_guid: 3, caster_level: 60, target_guid: 1, target_hostile?: true, hit_outcome: :hit}
      {c, events} = SpellEffect.receive(c, context, frostbolt, 1000)
      assert ids(c) == [1]
      assert c.unit.health == 950
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 50}, &1))
    end
  end

  defp ids(c), do: c.unit.auras |> Enum.map(& &1.spell.id) |> Enum.sort()

  defp slow(id, amount, duration, category \\ :snare) do
    aura = if category == :snare, do: :mod_decrease_speed, else: :mod_melee_haste

    %Spell{
      id: id,
      school: :frost,
      exclusive_category: category,
      duration_ms: duration,
      effects: [%Effect{index: 0, type: :apply_aura, aura: aura, base_points: amount, implicit_target_a: :target_enemy}]
    }
  end

  defp character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 1},
        unit: %Unit{
          health: 1000,
          max_health: 1000,
          level: 60,
          auras: [],
          base_melee_attack_time: 2000,
          base_attack_time: 2000,
          base_offhand_attack_time: 1500,
          offhand_attack_time: 1500
        },
        player: %Player{},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, base_run_speed: 7.0, run_speed: 7.0}
      }
    }
  end
end
