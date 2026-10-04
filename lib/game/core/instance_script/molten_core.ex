defmodule ThistleTea.Game.Core.InstanceScript.MoltenCore do
  @moduledoc """
  The runes of warding and Majordomo Executus's arrival, after vmangos
  `instance_molten_core` and `go_rune_MC`.

  Each of the seven lieutenants guards a rune. Once its lieutenant is dead,
  dousing a rune with Aqual or Eternal Quintessence puts out its circle of
  fire. Dousing it any earlier changes nothing, though unlike vmangos the rune
  still plays its use. When all seven are out, Majordomo Executus appears in
  his hall with his guard, and his defeat brings out the Cache of the Firelord
  for an hour. vmangos also calls a friendly Majordomo straight to Ragnaros's
  lair when the copy reloads after his defeat, which a world that never
  outlives a restart has no use for.

  Once Ragnaros has burned Majordomo to ash, the copy holds his last roar
  for seven seconds and lowers his immunity three seconds after it, pulling
  the whole raid into the fight; Ragnaros's own pending scripts would end
  the moment his kill left him out of combat.

  Boss deaths settle their encounters here, standing in for the vmangos boss
  scripts. Magmadar and Majordomo report their own. A boss's guard does not
  come back once the boss is dead: Lucifron's protectors, Magmadar's core
  hounds, Gehennas's flamewakers, Garr with his firesworn and lava surgers,
  Golemagg's core ragers, and Sulfuron's priests despawn whenever they
  respawn. Golemagg's ragers also vanish the moment he dies, since they
  cannot fall below half health while he lives.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.InstanceScript.Encounter

  @sulfuron 0
  @geddon 1
  @shazzrah 2
  @golemagg 3
  @garr 4
  @magmadar 5
  @gehennas 6
  @lucifron 7
  @majordomo 8
  @ragnaros 9
  @majordomo_summoned 23

  @done 3

  @bosses %{
    12_098 => @sulfuron,
    12_056 => @geddon,
    12_264 => @shazzrah,
    11_988 => @golemagg,
    12_057 => @garr,
    11_982 => @magmadar,
    12_259 => @gehennas,
    12_118 => @lucifron,
    11_502 => @ragnaros
  }

  @runes %{
    176_951 => {@sulfuron, 16, 43_157, 178_187},
    176_952 => {@geddon, 17, 43_158, 178_188},
    176_953 => {@shazzrah, 18, 43_159, 178_189},
    176_954 => {@golemagg, 19, 43_160, 178_190},
    176_955 => {@garr, 20, 43_165, 178_191},
    176_956 => {@magmadar, 21, 43_161, 178_192},
    176_957 => {@gehennas, 22, 43_163, 178_193}
  }

  @guards %{
    12_119 => @lucifron,
    11_671 => @magmadar,
    11_673 => @magmadar,
    11_661 => @gehennas,
    12_057 => @garr,
    12_099 => @garr,
    12_101 => @garr,
    11_672 => @golemagg,
    11_662 => @sulfuron
  }

  @golemagg_entry 11_988
  @core_rager 11_672
  @majordomo_entry 12_018
  @majordomo_hall {758.089, -1_176.71, -118.640, 3.12414}
  @corpse_timed 6
  @majordomo_corpse_ms 10_000
  @firelord_cache 362_148
  @hour_ms 3_600_000

  @ragnaros_entry 11_502
  @say_arrival 7_685
  @roar 15
  @roar_after_ms 7_000
  @engage_after_ms 3_000
  @unit_flags 46
  @immune_to_player 0x100
  @remove_flags 2

  def broadcast_text_ids, do: [@say_arrival]
  def summon_entries, do: [@majordomo_entry]
  def game_object_db_guids, do: [@firelord_cache]
  def door_entries, do: []
  def data64(_index), do: nil
  def initial_value(_field), do: 0

  def registered_fields do
    rune_fields = for {_boss, rune, _circle, _entry} <- Map.values(@runes), do: rune
    Enum.to_list(@sulfuron..@ragnaros) ++ Enum.sort(rune_fields) ++ [@majordomo_summoned]
  end

  def set_data(data, @majordomo, value) do
    stored = Encounter.settle(data, @majordomo, value)
    cache = if stored == @done and not Encounter.done?(data, @majordomo), do: [firelord_cache()], else: []
    {:ok, stored, Map.put(data, @majordomo, stored), cache}
  end

  def set_data(data, field, value) do
    stored = Encounter.settle(data, field, value)
    {:ok, stored, Map.put(data, field, stored), []}
  end

  def game_object_used(data, script_state, entry) when is_map_key(@runes, entry) do
    {boss, rune, circle, _circle_entry} = Map.fetch!(@runes, entry)

    if Encounter.done?(data, boss) do
      {data, summon} = data |> Map.put(rune, @done) |> summon_majordomo()
      {:ok, data, script_state, [%Effects.SuspendGameObject{db_guid: circle} | summon]}
    else
      {:ok, data, script_state, []}
    end
  end

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}

  def game_object_spawned(data, _script_state, entry) do
    effects =
      for {_entry, {_boss, rune, circle, ^entry}} <- @runes, Encounter.done?(data, rune) do
        %Effects.SuspendGameObject{db_guid: circle}
      end

    {:ok, effects}
  end

  def creature_event(data, script_state, %{creature_entry: @majordomo_entry, event: :death}) do
    {:ok, data, script_state, [%Effects.Schedule{key: :ragnaros_roars, delay_ms: @roar_after_ms}]}
  end

  def creature_event(data, script_state, %{creature_entry: entry, event: :death}) when is_map_key(@bosses, entry) do
    {:ok, _stored, data, effects} = set_data(data, Map.fetch!(@bosses, entry), @done)
    {:ok, data, script_state, effects ++ fallen_guard(entry)}
  end

  def creature_event(data, script_state, %{creature_entry: entry, event: :spawned, creature_guid: guid})
      when is_map_key(@guards, entry) do
    if Encounter.done?(data, Map.fetch!(@guards, entry)) do
      despawn = %Effects.RunCreatureScript{
        creature_entry: entry,
        creature_guid: guid,
        steps: [%ScriptStep{command: :despawn}]
      }

      {:ok, data, script_state, [despawn]}
    else
      {:ok, data, script_state, []}
    end
  end

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, :ragnaros_roars) do
    effects = [
      %Effects.MonsterTalk{creature_entry: @ragnaros_entry, broadcast_text_id: @say_arrival},
      %Effects.RunCreatureScript{
        creature_entry: @ragnaros_entry,
        steps: [%ScriptStep{command: :emote, datalong: @roar}]
      },
      %Effects.Schedule{key: :ragnaros_engages, delay_ms: @engage_after_ms}
    ]

    {:ok, data, script_state, effects}
  end

  def timer(data, script_state, :ragnaros_engages) do
    engage = [
      %ScriptStep{
        command: :modify_flags,
        datalong: @unit_flags,
        datalong2: @immune_to_player,
        datalong3: @remove_flags
      },
      %ScriptStep{command: :zone_combat_pulse}
    ]

    {:ok, data, script_state, [%Effects.RunCreatureScript{creature_entry: @ragnaros_entry, steps: engage}]}
  end

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp summon_majordomo(data) do
    runes_out? = Enum.all?(Map.values(@runes), fn {_boss, rune, _circle, _entry} -> Encounter.done?(data, rune) end)

    if runes_out? and not Encounter.done?(data, @ragnaros) and not Encounter.done?(data, @majordomo_summoned) and
         not Encounter.done?(data, @majordomo) do
      majordomo = %Effects.SummonCreature{
        entry: @majordomo_entry,
        position: @majordomo_hall,
        despawn_delay_ms: @majordomo_corpse_ms,
        despawn_type: @corpse_timed
      }

      {Map.put(data, @majordomo_summoned, @done), [majordomo]}
    else
      {data, []}
    end
  end

  defp fallen_guard(@golemagg_entry) do
    [%Effects.RunCreatureScript{creature_entry: @core_rager, steps: [%ScriptStep{command: :despawn}]}]
  end

  defp fallen_guard(_boss_entry), do: []

  defp firelord_cache, do: %Effects.RespawnGameObject{db_guid: @firelord_cache, duration_ms: @hour_ms}
end
