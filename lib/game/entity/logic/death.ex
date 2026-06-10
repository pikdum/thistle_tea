defmodule ThistleTea.Game.Entity.Logic.Death do
  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell

  @ghost_spell_id 8326
  @wisp_spell_id 20_584
  @resurrection_sickness_spell_id 15_007
  @night_elf_race 4

  @player_flag_ghost 0x10
  @unit_byte1_always_stand 0x01

  @reclaim_delay_ms 30_000
  @corpse_reclaim_radius 39.0
  @resurrection_sickness_level 11
  @resurrection_sickness_max_ms 600_000

  def ghost_spell_id, do: @ghost_spell_id
  def wisp_spell_id, do: @wisp_spell_id
  def resurrection_sickness_spell_id, do: @resurrection_sickness_spell_id
  def reclaim_delay_ms, do: @reclaim_delay_ms
  def corpse_reclaim_radius, do: @corpse_reclaim_radius

  def ghost_spell_ids(%{unit: %Unit{race: @night_elf_race}}), do: [@ghost_spell_id, @wisp_spell_id]
  def ghost_spell_ids(_character), do: [@ghost_spell_id]

  def ghost?(%{player: %Player{flags: flags}}) when is_integer(flags) do
    (flags &&& @player_flag_ghost) != 0
  end

  def ghost?(_entity), do: false

  def alive?(entity), do: not Core.dead?(entity) and not ghost?(entity)

  def release_spirit(%{unit: %Unit{} = unit, player: %Player{} = player} = character, ghost_spells, now) do
    character = %{
      character
      | unit: %{unit | health: 1, vis_flag: @unit_byte1_always_stand},
        player: %{player | flags: (player.flags || 0) ||| @player_flag_ghost}
    }

    {character, events} = apply_ghost_spells(character, ghost_spells, now)

    {Core.mark_broadcast_update(character), events ++ [Event.movement_root_changed(false)]}
  end

  def resurrect(%{unit: %Unit{}} = character, restore_percent, now) when restore_percent > 0 do
    {character, events} = Aura.remove_spells(character, [@ghost_spell_id, @wisp_spell_id], now)

    %{unit: unit, player: player} = character

    unit = %{
      unit
      | health: restore_value(unit.max_health, restore_percent),
        power1: restore_value(unit.max_power1, restore_percent),
        power2: 0,
        power4: restore_value(unit.max_power4, restore_percent),
        vis_flag: 0
    }

    player = %{player | flags: (player.flags || 0) &&& bnot(@player_flag_ghost)}

    character = %{character | unit: unit, player: player}

    {Core.mark_broadcast_update(character), events ++ [Event.movement_root_changed(false)]}
  end

  def resurrection_sickness_duration_ms(level) when is_integer(level) and level >= @resurrection_sickness_level do
    min((level - @resurrection_sickness_level + 1) * 60_000, @resurrection_sickness_max_ms)
  end

  def resurrection_sickness_duration_ms(_level), do: nil

  defp apply_ghost_spells(character, ghost_spells, now) do
    caster_guid = character.object.guid
    caster_level = character.unit.level

    Enum.reduce(ghost_spells, {character, []}, fn
      %Spell{} = spell, {character, events} ->
        {character, spell_events} = Aura.apply_spell(character, caster_guid, caster_level, spell, now)
        {character, events ++ spell_events}

      _spell, acc ->
        acc
    end)
  end

  defp restore_value(max, restore_percent) when is_integer(max) and max > 0 do
    max(trunc(max * restore_percent), 1)
  end

  defp restore_value(_max, _restore_percent), do: 0
end
