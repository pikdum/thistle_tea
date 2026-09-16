defmodule ThistleTea.Game.Entity.Logic.SwimSpeedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:character]

  describe "apply_spell/5" do
    test "swim bonuses change only forward swimming and cancellation restores it", %{character: character} do
      {boosted, events} = apply_spell(character, buff(1, :mod_increase_swim_speed, 100))
      assert speeds(events) == %{swim_speed: 9.444444}
      assert boosted.movement_block.run_speed == 7.0
      assert boosted.movement_block.swim_back_speed == 2.5
      {restored, events} = Aura.cancel_spell(boosted, 1, 2000)
      assert restored.movement_block == character.movement_block
      assert [%Effects.MovementSpeedChanged{movement_type: :swim_speed, speed: 4.722222}] = events
    end

    test "strongest bonus wins and expiry reveals the remaining bonus", %{character: character} do
      {boosted, _} = apply_spell(character, %{buff(1, :mod_increase_swim_speed, 50) | duration_ms: 10_000})
      {boosted, _} = apply_spell(boosted, buff(2, :mod_increase_swim_speed, 100))
      {boosted, events} = apply_spell(boosted, buff(3, :mod_increase_swim_speed, 25))
      assert speeds(events) == %{}
      assert boosted.movement_block.swim_speed == 9.444444
      {expired, events} = Aura.expire_due(boosted, 6000)
      assert_in_delta expired.movement_block.swim_speed, 7.083333, 0.000001
      assert [%Effects.MovementSpeedChanged{movement_type: :swim_speed}] = events
    end

    test "slows synchronize all affected modes and restore the swim bonus on removal", %{character: character} do
      {boosted, _} = apply_spell(character, buff(1, :mod_increase_swim_speed, 100))
      {slowed, events} = apply_spell(boosted, buff(2, :mod_decrease_speed, -50))
      assert speeds(events) == %{run_speed: 3.5, run_back_speed: 2.25, swim_speed: 4.722222}
      assert slowed.movement_block.swim_back_speed == 2.5
      {restored, events} = Aura.remove_spells(slowed, [2], 2000)
      assert restored.movement_block == boosted.movement_block
      assert speeds(events) == %{run_speed: 7.0, run_back_speed: 4.5, swim_speed: 9.444444}
    end

    test "death restores swimming and queues the client update", %{character: character} do
      {boosted, _} = apply_spell(character, buff(1, :mod_increase_swim_speed, 100))
      dead = Core.take_damage(boosted, 100, 2000)
      assert dead.unit.health == 0
      assert dead.movement_block.swim_speed == 4.722222

      assert Enum.any?(
               dead.internal.events,
               &match?(%Effects.MovementSpeedChanged{movement_type: :swim_speed, speed: 4.722222}, &1)
             )
    end
  end

  defp speeds(events) do
    Map.new(for %Effects.MovementSpeedChanged{} = effect <- events, do: {effect.movement_type, effect.speed})
  end

  defp apply_spell(character, spell), do: Aura.apply_spell(character, 1, 60, spell, 1000)

  defp buff(id, aura, amount) do
    %Spell{
      id: id,
      duration_ms: 5000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: aura, base_points: amount - 1, die_sides: 1, base_dice: 1}]
    }
  end

  defp character(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
      player: %Player{},
      internal: %Internal{},
      movement_block: struct!(%MovementBlock{movement_flags: 0}, MovementBlock.player_speeds())
    }

    %{character: character}
  end
end
