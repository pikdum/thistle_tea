defmodule ThistleTea.Game.Core.Creature.CreatureFlags do
  @moduledoc """
  Creature-template combat defaults, independent of runtime unit flags and
  script overrides. Static flags remain available on the entity after loading.

  `type_flags/2` derives the creature type flags the client reads from the
  creature query response out of the template's static flags, the way
  vmangos `CreatureInfo::GetTypeFlags` does; the raw static flags never go to
  the client.
  """

  import Bitwise

  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Pvp

  @flags %{
    no_xp: 0x00000002,
    unkillable: 0x00000008,
    immune_to_player: 0x00000020,
    immune_to_npc: 0x00000040,
    sessile: 0x00000100,
    uninteractible: 0x00000200,
    corpse_raid: 0x00001000,
    no_defense: 0x00004000,
    no_spell_defense: 0x00008000,
    no_melee: 0x00100000,
    pvp_enabling: 0x00400000,
    can_swim: 0x10000000
  }

  @unit_flags [immune_to_player: 0x100, immune_to_npc: 0x200, uninteractible: 0x02000000, can_swim: 0x8000]

  @type_flags [
    {:static_flags, 0x00000010, 0x01},
    {:static_flags, 0x00200000, 0x02},
    {:static_flags, 0x00010000, 0x04},
    {:static_flags, 0x00800000, 0x08},
    {:static_flags, 0x01000000, 0x10},
    {:static_flags, 0x40000000, 0x20},
    {:static_flags2, 0x00000008, 0x40}
  ]

  def has?(%{internal: %Internal{creature: %Creature{static_flags: flags}}}, flag), do: has?(flags, flag)
  def has?(flags, flag) when is_integer(flags), do: (flags &&& Map.fetch!(@flags, flag)) != 0
  def has?(_entity, _flag), do: false

  def no_wounded_slowdown?(%{internal: %Internal{creature: %Creature{static_flags2: flags}}}) when is_integer(flags),
    do: (flags &&& 0x40) != 0

  def no_wounded_slowdown?(_entity), do: false

  def no_owner_threat?(%{internal: %Internal{creature: %Creature{static_flags2: flags}}}) when is_integer(flags),
    do: (flags &&& 0x20) != 0

  def no_owner_threat?(_entity), do: false

  def no_threat_list?(%{internal: %Internal{creature: %Creature{extra_flags: flags}}}) when is_integer(flags),
    do: (flags &&& 0x800) != 0

  def no_threat_list?(_entity), do: false

  def guard?(%{internal: %Internal{creature: %Creature{extra_flags: flags}}}) when is_integer(flags),
    do: (flags &&& 0x400) != 0

  def guard?(_entity), do: false

  def locks_raid?(%{internal: %Internal{creature: %Creature{static_flags2: flags}}}) when is_integer(flags),
    do: (flags &&& 0x4) != 0

  def locks_raid?(_entity), do: false

  def force_raid_combat?(%{internal: %Internal{creature: %Creature{static_flags2: flags}}}) when is_integer(flags),
    do: (flags &&& 0x2) != 0

  def force_raid_combat?(_entity), do: false

  def unit_flags(flags, static_flags) do
    Enum.reduce(@unit_flags, Pvp.unit_flags(flags, has?(static_flags, :pvp_enabling)), fn {flag, mask}, acc ->
      if has?(static_flags, flag), do: acc ||| mask, else: acc &&& bnot(mask)
    end)
  end

  def type_flags(static_flags, static_flags2) do
    flags = %{static_flags: static_flags || 0, static_flags2: static_flags2 || 0}

    Enum.reduce(@type_flags, 0, fn {field, static_flag, type_flag}, acc ->
      if (Map.fetch!(flags, field) &&& static_flag) == 0, do: acc, else: acc ||| type_flag
    end)
  end

  def invincibility_threshold(flags, current \\ nil) do
    if has?(flags, :unkillable), do: if(is_integer(current) and current > 0, do: current, else: 1)
  end
end
