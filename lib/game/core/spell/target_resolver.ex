defmodule ThistleTea.Game.Core.Spell.TargetResolver do
  @moduledoc """
  Port for the launch-time target lookups that core cannot answer from the
  caster's own data: area and chain recipients, a target's hit defenses,
  line of sight, and insignia or resurrection bodies.

  Casting resolves targets synchronously at launch, so these calls happen
  inside core rather than through an effect round-trip. The world implements
  the contract (`World.Spell.SpellTargetResolver`), and
  `config :thistle_tea, :spell_target_resolver` wires it in, the same way
  Auth reaches the game server through config. A test can swap in a stub with
  `Application.put_env/3` from a synchronous case.
  """
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.Spell.UnitTargets

  @callback resolve(caster :: map(), spell :: %Spell{}, targets :: %Target{}, opts :: keyword()) :: [integer()]
  @callback resolve_plan(
              caster :: map(),
              spell :: %Spell{},
              targets :: %Target{},
              units :: %UnitTargets{},
              opts :: keyword()
            ) :: %UnitTargets{}
  @callback hit_defense(caster :: map(), target_guid :: integer()) :: map() | :unattackable
  @callback line_of_sight?(caster :: map(), target_guid :: integer()) :: boolean()
  @callback insignia_target(caster :: map(), spell :: %Spell{}, targets :: %Target{}) ::
              {:ok, integer()} | {:error, atom()}
  @callback resurrection_target(caster :: map(), spell :: %Spell{}, targets :: %Target{}) ::
              {:ok, integer()} | {:error, atom()}

  def resolve(caster, spell, targets, opts \\ []), do: impl().resolve(caster, spell, targets, opts)

  def resolve_plan(caster, spell, targets, units, opts), do: impl().resolve_plan(caster, spell, targets, units, opts)

  def hit_defense(caster, target_guid), do: impl().hit_defense(caster, target_guid)

  def line_of_sight?(caster, target_guid), do: impl().line_of_sight?(caster, target_guid)

  def insignia_target(caster, spell, targets), do: impl().insignia_target(caster, spell, targets)

  def resurrection_target(caster, spell, targets), do: impl().resurrection_target(caster, spell, targets)

  defp impl, do: Application.fetch_env!(:thistle_tea, :spell_target_resolver)
end
