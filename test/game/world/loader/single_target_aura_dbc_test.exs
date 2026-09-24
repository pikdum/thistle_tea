defmodule ThistleTea.Game.World.Loader.SingleTargetAuraDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Aura.SingleTarget
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db
  @spells [
    118,
    12_826,
    28_271,
    28_272,
    1130,
    14_325,
    5782,
    6215,
    710,
    18_647,
    339,
    9853,
    2637,
    18_658,
    20_184,
    20_185,
    20_186
  ]

  setup [:flags]

  describe "load/1" do
    test "classifies alternate polymorph models and judgement types as shared limits" do
      for ids <- [[118, 12_826, 28_271, 28_272], [20_184, 20_185, 20_186]] do
        for first <- ids, second <- ids do
          assert SingleTarget.conflicts?(claim(first, 2), claim(second, 3))
        end
      end
    end

    test "matches ranks while preserving independent control families" do
      for {first, second} <- [{1130, 14_325}, {5782, 6215}, {710, 18_647}, {339, 9853}, {2637, 18_658}] do
        assert SingleTarget.conflicts?(claim(first, 2), claim(second, 3))
      end

      for {first, second} <- [{5782, 710}, {339, 2637}, {118, 1130}] do
        refute SingleTarget.conflicts?(claim(first, 2), claim(second, 3))
      end
    end
  end

  defp claim(id, target) do
    spell = SpellLoader.load(id)
    holder = %Holder{spell: spell, caster_guid: 1, single_target_generation: 1}
    [claim] = SingleTarget.claims([holder], target)
    claim
  end

  defp flags(_context) do
    previous = for id <- @spells, entry <- :ets.lookup(SpellEffectOverride, {:custom_flags, id}), do: entry
    for id <- @spells, do: :ets.insert(SpellEffectOverride, {{:custom_flags, id}, 256})

    on_exit(fn ->
      for id <- @spells, do: :ets.delete(SpellEffectOverride, {:custom_flags, id})
      :ets.insert(SpellEffectOverride, previous)
    end)

    :ok
  end
end
