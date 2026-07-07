defmodule ThistleTea.Game.Aura.Holder do
  @moduledoc """
  All auras applied by one cast of a spell on a unit: source spell and caster,
  display slot, expiry, and the contained `Aura` effects — plus the predicates
  shared by the aura subsystem (type membership, source identity, expiry,
  interruptibility).
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Spell

  defstruct [
    :spell,
    :caster_guid,
    :caster_level,
    :slot,
    :applied_at,
    :expires_at,
    :charges,
    auras: [],
    stacks: 1,
    negative?: false
  ]

  def has_aura_type?(%__MODULE__{auras: auras}, type) do
    Enum.any?(auras, fn %Aura{type: t} -> t == type end)
  end

  def has_any_type?(%__MODULE__{auras: auras}, types) do
    Enum.any?(auras, fn %Aura{type: type} -> type in types end)
  end

  def same_source?(%__MODULE__{spell: %Spell{id: id}, caster_guid: caster}, spell_id, caster_guid) do
    id == spell_id and caster == caster_guid
  end

  def same_source?(_holder, _spell_id, _caster_guid), do: false

  def alive?(%__MODULE__{expires_at: nil}, _now), do: true
  def alive?(%__MODULE__{expires_at: -1}, _now), do: true
  def alive?(%__MODULE__{expires_at: expires_at}, now) when is_integer(expires_at), do: now < expires_at
  def alive?(_holder, _now), do: true

  def interruptible?(%__MODULE__{spell: %Spell{aura_interrupt_flags: flags}}, mask) when is_integer(flags) do
    (flags &&& mask) != 0
  end

  def interruptible?(_holder, _mask), do: false
end
