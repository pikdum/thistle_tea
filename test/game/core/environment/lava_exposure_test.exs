defmodule ThistleTea.Game.Core.Environment.LavaExposureTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BehaviorRunner
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Random
  alias ThistleTea.Game.Core.AI.BT.Player, as: PlayerBT
  alias ThistleTea.Game.Core.AI.Tick
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Environment.LavaExposure
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Terrain.Liquid

  @lava %Liquid{flags: 1, surface: 0.0, floor: -10.0}

  setup [:character]

  describe "update/5" do
    test "burns after one second and every two seconds without a client mirror bar", %{character: character} do
      entered = update(character, @lava, 0)
      assert entered.internal.events == []
      assert entered.unit.health == 3000
      assert LavaExposure.next_tick_at(entered) == 1000
      assert update(entered, @lava, 999).unit.health == 3000
      first = update(entered, @lava, 1000)
      assert first.unit.health == 2395
      assert %Effects.EnvironmentalDamage{type: :lava, damage: 605} in first.internal.events
      refute Enum.any?(first.internal.events, &is_struct(&1, Effects.StartMirrorTimer))
      assert LavaExposure.next_tick_at(first) == 3000
      assert update(first, @lava, 2999).unit.health == 2395
      assert update(first, @lava, 3000).unit.health == 1790
      assert update(first, @lava, 60_000).unit.health == 1790
    end

    test "surface proximity includes water walking but excludes jumping and harmless liquids", %{character: c} do
      assert update(at_height(c, 0.08), @lava, 0).internal.lava_exposure != nil
      assert update(at_height(c, 0.1), @lava, 0) == at_height(c, 0.1)

      for liquid <- [nil, %{@lava | flags: 2}, %{@lava | flags: 4}, %{@lava | flags: 8}] do
        assert update(c, liquid, 1000) == c
      end
    end

    test "recovers at ten times speed and preserves partial reserves on reentry", %{character: c} do
      first = c |> update(@lava, 0) |> update(@lava, 1000)
      jumping = first |> at_height(1.0) |> update(@lava, 1000)
      assert jumping.internal.lava_exposure.scale == 10
      assert LavaExposure.next_tick_at(jumping) == 1100
      landed = jumping |> at_height(0.0) |> update(@lava, 1050)
      assert landed.internal.lava_exposure.remaining == 500
      assert LavaExposure.next_tick_at(landed) == 1550
      assert update(landed, @lava, 1549).unit.health == 2395
      assert update(landed, @lava, 1550).unit.health == 1790
      assert update(jumping, @lava, 1100).internal.lava_exposure == nil
      assert update(first, nil, 3000).internal.lava_exposure == nil
      assert update(first, nil, 3000).unit.health == 2395
    end

    test "depletes fire shields across pulses and never restores a consumed holder", %{character: c} do
      shielded = with_aura(c, :school_absorb, 700, 4)
      first = shielded |> update(@lava, 0) |> update(@lava, 1000)
      assert first.unit.health == 3000
      assert hd(hd(first.unit.auras).auras).amount == 95
      second = update(first, @lava, 3000)
      assert second.unit.health == 2490
      assert second.unit.auras == []
      third = update(second, @lava, 5000)
      assert third.unit.health == 1885
      assert third.unit.auras == []
    end

    test "uses supplied resistance rolls and leaves Water Breathing ineffective", %{character: c} do
      resistant = %{c | unit: %{c.unit | fire_resistance: 300}} |> update(@lava, 0)
      resisted = LavaExposure.update(resistant, @lava, 1000, 608, 0)
      assert resisted.unit.health == 2848
      assert %Effects.EnvironmentalDamage{type: :lava, damage: 152, resisted: 456} in resisted.internal.events
      breathing = with_aura(c, :water_breathing, 0, 0) |> update(@lava, 0)
      assert update(breathing, @lava, 1000).unit.health == 2395
      immune = with_aura(c, :school_immunity, 0, 4) |> update(@lava, 0)
      assert update(immune, @lava, 1000).unit.health == 3000
      assert update(immune, @lava, 1000).internal.events == []
    end

    test "death uses shared cleanup and bodies ghosts and Spirit of Redemption cannot burn", %{character: c} do
      entered = %{c | unit: %{c.unit | health: 100}} |> update(@lava, 0)
      dead = update(entered, @lava, 1000)
      assert dead.unit.health == 0
      assert dead.internal.lava_exposure == nil
      assert %Effects.DurabilityDamage{source_guid: nil, lethal?: true, environmental?: true} in dead.internal.events
      assert %Effects.MovementRootChanged{rooted?: true} in dead.internal.events
      assert update(dead, @lava, 3000) == dead

      for protected <- [
            %{entered | player: %{entered.player | flags: 0x10}},
            %{entered | unit: %{entered.unit | shapeshift_form: 32}},
            %{entered | internal: %{entered.internal | godmode: true}}
          ] do
        result = update(protected, @lava, 1000)
        assert result.unit.health == 100
        assert result.internal.lava_exposure == nil
        assert result.internal.events == []
      end
    end
  end

  describe "tick/3" do
    test "stationary deadlines and damage rolls come from the behavior context", %{character: c} do
      context = Context.new(0, terrain_liquid: @lava, random: Random.fixed(0.5, 6))
      {:running, entered} = BehaviorRunner.tick(PlayerBT.tree(), c, context)
      assert Tick.needs_tick?(entered)
      assert Tick.player_delay(entered, {:running, 10_000}, 0) == 1000
      {:running, burned} = BehaviorRunner.tick(PlayerBT.tree(), entered, %{context | now: 1000})
      assert burned.unit.health == 2390
      assert Tick.player_delay(burned, {:running, 10_000}, 1000) <= 2000
      {:running, exited} = BehaviorRunner.tick(PlayerBT.tree(), burned, %{context | now: 1001, terrain_liquid: nil})
      assert LavaExposure.next_tick_at(exited) == nil
    end
  end

  defp update(character, liquid, now), do: LavaExposure.update(character, liquid, now, 605, 99)

  defp at_height(character, z),
    do: %{character | movement_block: %{character.movement_block | position: {0.0, 0.0, z, 0.0}}}

  defp with_aura(character, type, amount, mask) do
    aura = %Aura{type: type, amount: amount, misc_value: mask}
    holder = %Holder{spell: %Spell{id: 999}, caster_guid: 1, auras: [aura]}
    %{character | unit: %{character.unit | auras: [holder]}}
  end

  defp character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 1},
        player: %Player{flags: 0},
        unit: %Unit{health: 3000, max_health: 3000, level: 60, auras: [], fire_resistance: 0},
        internal: %Internal{},
        movement_block: %MovementBlock{movement_flags: 0, position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end
end
