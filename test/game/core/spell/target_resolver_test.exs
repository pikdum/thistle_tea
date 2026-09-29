defmodule ThistleTea.Game.Core.Spell.TargetResolverTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.Spell.TargetResolver
  alias ThistleTea.Game.Core.Spell.UnitTargets

  defmodule Stub do
    @moduledoc false
    @behaviour TargetResolver

    @impl TargetResolver
    def resolve(_caster, %Spell{id: id}, _targets, _opts), do: [id]

    @impl TargetResolver
    def resolve_plan(_caster, _spell, _targets, units, _opts), do: units

    @impl TargetResolver
    def hit_defense(_caster, _target_guid), do: :unattackable

    @impl TargetResolver
    def line_of_sight?(_caster, target_guid), do: target_guid == 7

    @impl TargetResolver
    def insignia_target(_caster, _spell, _targets), do: {:error, :bad_targets}

    @impl TargetResolver
    def resurrection_target(_caster, _spell, _targets), do: {:ok, 9}
  end

  setup do
    previous = Application.fetch_env!(:thistle_tea, :spell_target_resolver)
    Application.put_env(:thistle_tea, :spell_target_resolver, Stub)
    on_exit(fn -> Application.put_env(:thistle_tea, :spell_target_resolver, previous) end)
  end

  describe "resolve/4" do
    test "delegates to the configured implementation" do
      caster = %{object: %{guid: 1}}
      spell = %Spell{id: 133}

      assert TargetResolver.resolve(caster, spell, Target.none()) == [133]
      assert TargetResolver.resolve_plan(caster, spell, Target.none(), %UnitTargets{}, []) == %UnitTargets{}
      assert TargetResolver.hit_defense(caster, 7) == :unattackable
      assert TargetResolver.line_of_sight?(caster, 7)
      refute TargetResolver.line_of_sight?(caster, 8)
      assert TargetResolver.insignia_target(caster, spell, Target.none()) == {:error, :bad_targets}
      assert TargetResolver.resurrection_target(caster, spell, Target.none()) == {:ok, 9}
    end
  end
end
