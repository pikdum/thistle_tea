defmodule ThistleTea.Game.World.Loader.StealthDetectionDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.StealthDetection
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "Perception, Paranoia and Track Hidden grant stealth detection while Detect Traps does not" do
      for {id, bonus} <- [{20_600, 50}, {19_480, 30}, {19_885, 30}, {2_836, 0}, {23_330, -500}] do
        spell = SpellLoader.load(id)
        {entity, _events} = Aura.apply_spell(character(), 1, 10, spell, 0)
        assert StealthDetection.target_metadata(entity).stealth_detection_bonus == bonus
      end
    end

    test "Perception expires and cancels through ordinary aura transitions" do
      spell = SpellLoader.load(20_600)
      assert spell.duration_ms == 20_000
      {entity, _events} = Aura.apply_spell(character(), 1, 10, spell, 0)
      target = %{level: 10, player?: true, stealthed?: true, stealth_skill: 50}

      assert StealthDetection.detectable?(StealthDetection.target_metadata(entity), target, 24.0, 19_999)
      {expired, _events} = Aura.expire_due(entity, 20_000)
      refute StealthDetection.detectable?(StealthDetection.target_metadata(expired), target, 24.0, 20_000)
      assert StealthDetection.target_metadata(expired).stealth_detection_bonus == 0

      {cancelled, _events} = Aura.cancel_spell(entity, spell.id, 1_000)
      assert StealthDetection.target_metadata(cancelled).stealth_detection_bonus == 0
    end

    test "death removes stealth and temporary detection bonuses" do
      entity =
        Enum.reduce([1_784, 20_600], character(), fn id, entity ->
          entity |> Aura.apply_spell(1, 10, SpellLoader.load(id), 0) |> elem(0)
        end)

      assert StealthDetection.target_metadata(entity).stealthed?
      assert StealthDetection.target_metadata(entity).stealth_detection_bonus == 50

      dead = Core.take_damage(entity, 1_000, 1_000)
      refute StealthDetection.target_metadata(dead).stealthed?
      assert StealthDetection.target_metadata(dead).stealth_detection_bonus == 0
    end
  end

  defp character do
    %Character{
      object: %Object{guid: 1},
      player: %Player{},
      movement_block: %MovementBlock{},
      unit: %Unit{level: 10, health: 100, max_health: 100, auras: []},
      internal: %Internal{}
    }
  end
end
