defmodule ThistleTea.Game.Entity.Logic.Honor.ProtectionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Pvp
  alias ThistleTea.Game.Entity.Data.Taxi.Flight
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Honor.Protection
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:build_character]

  describe "apply/3" do
    test "refreshes a single holder and expires at the loaded duration", %{character: character, spell: spell} do
      protected = Protection.apply(character, spell, 1_000)
      assert Aura.has_aura?(protected, :honorless_target)
      assert [%{expires_at: 31_000}] = protected.unit.auras
      refreshed = Protection.apply(protected, spell, 15_000)
      assert [%{expires_at: 45_000}] = refreshed.unit.auras
      {retained, []} = Aura.expire_due(refreshed, 44_999)
      assert Aura.has_aura?(retained, :honorless_target)
      {expired, _events} = Aura.expire_due(retained, 45_000)
      refute Aura.has_aura?(expired, :honorless_target)
    end

    test "excludes friendly territory, corpses, and ghosts", %{character: character, spell: spell} do
      friendly = %{character | internal: %{character.internal | pvp: %Pvp{desired?: true, remaining_ms: 300_000}}}
      corpse = %{character | unit: %{character.unit | health: 0}}
      ghost = %{character | unit: %{character.unit | health: 1}, player: %{character.player | flags: 0x10}}

      for ineligible <- [friendly, corpse, ghost] do
        refute Protection.eligible?(ineligible)
        assert Protection.apply(ineligible, spell, 1_000) == ineligible
      end

      assert Protection.apply(character, nil, 1_000) == character
    end

    test "safe arrival does not refresh existing protection and flight cannot grant it", %{
      character: character,
      spell: spell
    } do
      protected = Protection.apply(character, spell, 1_000)
      safe = %{protected | internal: %{protected.internal | pvp: %Pvp{}}}
      assert Protection.apply(safe, spell, 15_000) == safe

      flight = %Flight{
        token: make_ref(),
        path_ids: [1],
        source_node_id: 1,
        destination_node_id: 2,
        destination_position: {0.0, 0.0, 0.0},
        mount_display_id: 1,
        started_at: 1_000,
        duration_ms: 60_000
      }

      flying = %{character | internal: %{character.internal | taxi_flight: flight}}
      refute Protection.eligible?(flying)
      assert Protection.apply(flying, spell, 15_000) == flying
    end

    test "taking damage preserves protection and captures it before death cleanup", %{
      character: character,
      spell: spell
    } do
      protected = character |> Protection.apply(spell, 1_000) |> Core.take_damage(10, 2_000, source: 2)
      assert protected.unit.health == 90
      assert Aura.has_aura?(protected, :honorless_target)
      dead = Core.take_damage(protected, 100, 3_000, source: 2)
      assert dead.unit.health == 0
      refute Aura.has_aura?(dead, :honorless_target)
      assert Enum.any?(dead.internal.events, &match?(%Effects.HonorDamage{lethal?: true, honorless?: true}, &1))
    end
  end

  defp build_character(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 100, max_health: 100, auras: []},
      player: %Player{flags: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, spline_nodes: []},
      internal: %Internal{pvp: %Pvp{enforced?: true}}
    }

    spell = %Spell{
      id: 2479,
      duration_ms: 30_000,
      aura_interrupt_flags: 0x1000,
      effects: [%Effect{type: :apply_aura, aura: :honorless_target, implicit_target_a: :caster}]
    }

    %{character: character, spell: spell}
  end
end
