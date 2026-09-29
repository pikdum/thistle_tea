defmodule ThistleTea.Game.Core.Combat.SheathTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Combat.Sheath
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.WorldRef

  @sheathing 0x200

  setup [:character]

  describe "request/3" do
    test "sets the sheath byte and marks the unit for broadcast", %{character: character} do
      sheathed = Sheath.request(character, 1, 1_000)

      assert sheathed.unit.sheath_state == 1
      assert sheathed.internal.broadcast_update?
    end

    test "ignores unknown sheath states", %{character: character} do
      assert Sheath.request(character, 3, 1_000) == character
    end

    test "interrupts channels that break on sheathing", %{character: character} do
      channel = %Spell{id: 700, attributes: MapSet.new([:channeled]), channel_interrupt_flags: @sheathing}
      steady = %{channel | id: 701, channel_interrupt_flags: 0}

      interrupted = character |> channeling(channel) |> Sheath.request(1, 1_000)
      kept = character |> channeling(steady) |> Sheath.request(1, 1_000)

      assert interrupted.internal.casting == nil
      assert Enum.any?(interrupted.internal.events, &match?(%Effects.SpellCastFailed{spell_id: 700}, &1))
      assert %Cast{} = kept.internal.casting
    end

    test "removes auras that break on sheathing", %{character: character} do
      {character, _events} = Aura.apply_spell(character, 1, 60, aura_spell(800, @sheathing), 500)
      {character, _events} = Aura.apply_spell(character, 1, 60, aura_spell(801, 0), 500)

      sheathed = Sheath.request(character, 0, 1_000)

      assert Enum.map(sheathed.unit.auras, & &1.spell.id) == [801]
    end
  end

  describe "put/2" do
    test "leaves an unchanged sheath state unmarked", %{character: character} do
      assert Sheath.put(character, 0) == character
      assert Sheath.put(character, 7) == character
      assert Sheath.put(character, 2).unit.sheath_state == 2
    end
  end

  defp channeling(character, spell) do
    %{
      character
      | internal: %{character.internal | casting: %Cast{spell: spell, phase: :channel_tick, channel_ms: 5_000}}
    }
  end

  defp aura_spell(id, aura_interrupt_flags) do
    %Spell{
      id: id,
      duration_ms: 60_000,
      aura_interrupt_flags: aura_interrupt_flags,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stat, base_points: 1, die_sides: 0, misc_value: 0}]
    }
  end

  defp character(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 100, max_health: 100, sheath_state: 0, auras: []},
      player: %Player{},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{character: character}
  end
end
