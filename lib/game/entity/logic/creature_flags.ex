defmodule ThistleTea.Game.Entity.Logic.CreatureFlags do
  @moduledoc """
  Creature-template combat defaults, independent of runtime unit flags and
  script overrides. Static flags remain available on the entity after loading.
  """

  import Bitwise

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Logic.Pvp

  @flags %{
    unkillable: 0x00000008,
    immune_to_player: 0x00000020,
    immune_to_npc: 0x00000040,
    sessile: 0x00000100,
    uninteractible: 0x00000200,
    no_defense: 0x00004000,
    no_spell_defense: 0x00008000,
    no_melee: 0x00100000,
    pvp_enabling: 0x00400000,
    can_swim: 0x10000000
  }

  @unit_flags [immune_to_player: 0x100, immune_to_npc: 0x200, uninteractible: 0x02000000, can_swim: 0x8000]

  def has?(%{internal: %Internal{creature: %Creature{static_flags: flags}}}, flag), do: has?(flags, flag)
  def has?(flags, flag) when is_integer(flags), do: (flags &&& Map.fetch!(@flags, flag)) != 0
  def has?(_entity, _flag), do: false

  def no_wounded_slowdown?(%{internal: %Internal{creature: %Creature{static_flags2: flags}}}) when is_integer(flags),
    do: (flags &&& 0x40) != 0

  def no_wounded_slowdown?(_entity), do: false

  def locks_raid?(%{internal: %Internal{creature: %Creature{static_flags2: flags}}}) when is_integer(flags),
    do: (flags &&& 0x4) != 0

  def locks_raid?(_entity), do: false

  def unit_flags(flags, static_flags) do
    Enum.reduce(@unit_flags, Pvp.unit_flags(flags, has?(static_flags, :pvp_enabling)), fn {flag, mask}, acc ->
      if has?(static_flags, flag), do: acc ||| mask, else: acc &&& bnot(mask)
    end)
  end

  def invincibility_threshold(flags, current \\ nil) do
    if has?(flags, :unkillable), do: if(is_integer(current) and current > 0, do: current, else: 1)
  end
end
