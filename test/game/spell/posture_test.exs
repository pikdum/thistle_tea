defmodule ThistleTea.Game.Spell.PostureTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Emote
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Posture
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:caster]

  describe "validate/3" do
    test "shares standing requirements across players and creatures", %{caster: player, spell: spell} do
      mob = %Mob{unit: player.unit}

      for caster <- [player, mob], posture <- [1, 2, 3, 4, 5, 6, 8] do
        seated = %{caster | unit: %{caster.unit | stand_state: posture}}
        assert Posture.validate(seated, spell) == {:error, :not_standing}
        assert Posture.validate(seated, spell, triggered?: true) == :ok
        assert Posture.validate(seated, spell, cast_item_guid: 42) == {:error, :not_standing}
        assert Posture.validate(seated, %{spell | attributes: MapSet.new([:allow_while_sitting])}) == :ok
      end

      for posture <- [nil, 0, 7] do
        assert Posture.validate(%{player | unit: %{player.unit | stand_state: posture}}, spell) == :ok
      end

      assert Posture.validate(%GameObject{}, spell) == :ok
    end

    test "seated consumables require stationary players but allow turning", %{caster: caster, spell: spell} do
      food = %{spell | aura_interrupt_flags: 0x40000, attributes: MapSet.new([:allow_while_sitting])}

      for flags <- [1, 2, 4, 8, 0x40, 0x80, 0x2000, 0x4000, 0x04000000] do
        moving = %{caster | movement_block: %{caster.movement_block | movement_flags: flags}}
        assert Posture.validate(moving, food) == {:error, :moving}
        assert Posture.validate(moving, food, cast_item_guid: 42) == {:error, :moving}
        assert Posture.validate(moving, food, triggered?: true) == {:error, :moving}
        assert Posture.validate(moving, spell) == :ok
        assert Posture.validate(%Mob{unit: moving.unit, movement_block: moving.movement_block}, food) == :ok
      end

      for flags <- [nil, 0, 0x10, 0x20, 0x100, 0x00200000, 0x02000000] do
        stationary = %{caster | movement_block: %{caster.movement_block | movement_flags: flags}}
        assert Posture.validate(stationary, food) == :ok
      end
    end
  end

  describe "validate/6" do
    test "rejects seated admission before spending power", %{caster: caster, spell: spell, target: target} do
      caster = Emote.stand(caster, 1, 1_000)
      assert CastValidation.validate(caster, spell, target, :self, 1_000) == {:error, :not_standing}
      assert CastValidation.validate(caster, spell, target, :self, 1_000, triggered?: true) == :ok
    end
  end

  describe "complete/2" do
    test "sitting during preparation fails launch before costs and cooldowns", ctx do
      failed =
        ctx.caster
        |> Casting.start(ctx.spell, ctx.target, 1_000)
        |> Emote.stand(1, 1_500)
        |> Casting.complete(2_000)

      assert_failed(failed, :not_standing)
      assert failed.unit.stand_state == 1

      completed =
        ctx.caster
        |> Casting.start(ctx.spell, ctx.target, 1_000)
        |> Emote.stand(1, 1_400)
        |> Emote.stand(0, 1_500)
        |> Casting.complete(2_000)

      assert completed.unit.health > 50
      assert completed.unit.power1 == 70
      assert Enum.any?(completed.internal.events, &is_struct(&1, Effects.SpellGo))
    end

    test "movement during preparation rejects seated consumption", ctx do
      spell = %{ctx.spell | aura_interrupt_flags: 0x40000, attributes: MapSet.new([:allow_while_sitting])}
      started = Casting.start(ctx.caster, spell, ctx.target, 1_000)
      moving = %{started | movement_block: %{started.movement_block | movement_flags: 1}}
      assert_failed(Casting.complete(moving, 2_000), :moving)
    end

    test "triggered healing can finish while seated", ctx do
      completed =
        ctx.caster
        |> Emote.stand(1, 1_000)
        |> Casting.start_triggered(ctx.spell, ctx.target, 1_000, nil)

      assert completed.unit.health > 50
      assert completed.unit.power1 == 100
      assert completed.unit.stand_state == 1
      refute Enum.any?(completed.internal.events, &is_struct(&1, Effects.SpellCastFailed))
    end
  end

  defp assert_failed(entity, reason) do
    assert entity.internal.casting == nil
    assert entity.internal.cooldowns == %{}
    assert entity.unit.health == 50
    assert entity.unit.power1 == 100
    refute Enum.any?(entity.internal.events, &is_struct(&1, Effects.SpellGo))
    assert Enum.any?(entity.internal.events, &match?(%Effects.SpellCastFailed{reason: ^reason}, &1))
  end

  defp caster(_context) do
    %{
      caster: %Character{
        object: %Object{guid: 1},
        unit: %Unit{level: 10, health: 50, max_health: 100, power1: 100, max_power1: 100, auras: []},
        player: %Player{},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{movement_flags: 0, position: {0.0, 0.0, 0.0, 0.0}}
      },
      spell: %Spell{
        id: 900_852,
        school: :holy,
        mana_cost: 30,
        power_type: 0,
        cast_time_ms: 1_000,
        recovery_time_ms: 5_000,
        effects: [%Effect{index: 0, type: :heal, implicit_target_a: :caster, base_points: 9}]
      },
      target: Target.self(1)
    }
  end
end
