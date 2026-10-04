defmodule ThistleTea.Game.Core.Aura.DummyFlagsTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect

  @immune 0x300
  @not_selectable 0x02000000

  describe "apply_spell/5" do
    test "Stoned leaves a creature unselectable until it wears off" do
      {stoned, _events} = Aura.apply_spell(statue(@immune), 1, 40, stoned(), 1_000)
      assert stoned.unit.flags == (@immune ||| @not_selectable)

      {awake, _events} = Aura.remove_spells(stoned, [10_255], 2_000)
      assert awake.unit.flags == @immune
    end

    test "a creature already unselectable stays so when Stoned arrives" do
      flags = @immune ||| @not_selectable
      {stoned, _events} = Aura.apply_spell(statue(flags), 1, 40, stoned(), 1_000)
      assert stoned.unit.flags == flags
    end

    test "leaves players selectable" do
      {stoned, _events} = Aura.apply_spell(player(), 1, 60, stoned(), 1_000)
      assert stoned.unit.flags == 0
    end
  end

  defp statue(flags) do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 40, flags: flags, auras: []},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp player do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 60, flags: 0, auras: []},
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp stoned do
    %Spell{
      id: 10_255,
      duration_ms: -1,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :dummy, implicit_target_a: :caster}]
    }
  end
end
