defmodule ThistleTea.Game.Spell.SupportMatrixVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DBC
  alias ThistleTea.Game.Spell.SupportMatrix
  alias ThistleTea.Game.World.Loader.ClassSpell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db

  @classes [1, 2, 3, 4, 5, 7, 8, 9, 11]
  @max_level 60

  setup_all do
    :ok = SpellEffectOverride.load_all()
  end

  test "every trainable class spell resolves inside the support matrix" do
    spellbook =
      @classes
      |> Enum.flat_map(&ClassSpell.trainable_spell_ids(&1, @max_level))
      |> Enum.uniq()
      |> SpellLoader.build_spellbook()

    unknowns =
      for {_id, spell} <- spellbook,
          effect <- spell.effects,
          unknown <- effect_unknowns(spell, effect),
          uniq: true,
          do: unknown

    assert Enum.sort(unknowns) == []
  end

  test "every talent rank spell resolves inside the support matrix" do
    spellbook =
      Talent
      |> DBC.all()
      |> Enum.flat_map(fn row ->
        for index <- 0..8,
            spell_id = Map.get(row, :"spell_rank_#{index}"),
            is_integer(spell_id) and spell_id > 0,
            do: spell_id
      end)
      |> Enum.uniq()
      |> SpellLoader.build_spellbook()

    unknowns =
      for {_id, spell} <- spellbook,
          effect <- spell.effects,
          unknown <- effect_unknowns(spell, effect),
          uniq: true,
          do: unknown

    assert Enum.sort(unknowns) == []
  end

  defp effect_unknowns(spell, effect) do
    [
      if(!SupportMatrix.known_effect?(effect.type), do: {:effect, effect.type, spell.id}),
      if(!SupportMatrix.known_aura?(effect.aura), do: {:aura, effect.aura, spell.id}),
      if(!SupportMatrix.known_target?(effect.implicit_target_a), do: {:target, effect.implicit_target_a, spell.id}),
      if(!SupportMatrix.known_target?(effect.implicit_target_b), do: {:target, effect.implicit_target_b, spell.id})
    ]
    |> Enum.reject(&is_nil/1)
  end
end
