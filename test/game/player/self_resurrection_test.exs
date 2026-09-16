defmodule ThistleTea.Game.Player.SelfResurrectionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Player.SelfResurrection
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:build_character]

  describe "prepare/4" do
    test "preserves an incomplete character without player fields", %{character: character} do
      character = %{character | player: nil}
      assert SelfResurrection.prepare(character, 1_000) == character
    end

    test "offers learned Reincarnation only with a carried Ankh", %{character: character, spell: spell, ankh: ankh} do
      get_spell = fn 21_169 -> spell end
      get_item = fn 123 -> ankh end
      assert SelfResurrection.prepare(character, 1_000, get_spell, get_item).player.self_res_spell == 21_169
      assert SelfResurrection.prepare(character, 1_000, get_spell, fn _ -> nil end).player.self_res_spell == 0
    end

    test "rejects Reincarnation during cooldown", %{character: character, spell: spell, ankh: ankh} do
      character = %{character | internal: %{character.internal | cooldowns: %{{:category, 1161} => 2_000}}}
      assert SelfResurrection.prepare(character, 1_999, fn _ -> spell end, fn _ -> ankh end).player.self_res_spell == 0

      assert SelfResurrection.prepare(character, 2_000, fn _ -> spell end, fn _ -> ankh end).player.self_res_spell ==
               21_169
    end

    test "prioritizes a captured Soulstone without spending an Ankh", %{character: character} do
      character = %{character | player: %{character.player | self_res_spell: 3026}}
      spell = %Spell{id: 3026, effects: [%Effect{type: :self_resurrect}]}

      prepared =
        SelfResurrection.prepare(character, 1_000, fn 3026 -> spell end, fn _ -> flunk("Soulstone needs no reagent") end)

      assert prepared.player.self_res_spell == 3026
    end

    test "does not offer an unknown or malformed resurrection spell", %{character: character} do
      assert SelfResurrection.prepare(character, 1_000, fn _ -> nil end, fn _ -> nil end).player.self_res_spell == 0

      malformed = SelfResurrection.prepare(character, 1_000, fn _ -> %Spell{id: 21_169} end, fn _ -> nil end)
      assert malformed.player.self_res_spell == 0
    end
  end

  describe "use/1" do
    test "ignores requests before login or while alive", %{character: character} do
      state = %{ready: false, character: character}
      assert SelfResurrection.use(state) == state
      state = %{ready: true, character: %{character | unit: %{character.unit | health: 100}}}
      assert SelfResurrection.use(state) == state
    end
  end

  defp build_character(_context) do
    spell = %Spell{id: 21_169, category: 1161, reagents: [{17_030, 1}], effects: [%Effect{type: :self_resurrect}]}

    character = %Character{
      unit: %Unit{health: 0},
      player: %Player{self_res_spell: 0, inv1: 123},
      internal: %Internal{spellbook: %{20_608 => %Spell{id: 20_608}}}
    }

    ankh = Item.build(%ItemTemplate{entry: 17_030}, 123)
    %{character: character, spell: spell, ankh: ankh}
  end
end
