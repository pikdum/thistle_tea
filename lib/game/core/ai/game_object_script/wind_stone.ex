defmodule ThistleTea.Game.Core.AI.GameObjectScript.WindStone do
  @moduledoc """
  vmangos `go_wind_stone`: the wind stones of Silithus answer a player in
  Twilight's Hammer regalia. Speaking at a stone casts a summon spell whose
  activate object effect reaches the stone, and the stone calls up one of the
  Abyssal Council in its place before vanishing until it respawns. Lesser
  stones call a templar, wind stones a duke, and greater stones a royal; the
  plain challenge calls one at random from its rank, while a crest, signet, or
  scepter calls the lord of its element. Each summoning spends the Twilight
  Trappings the player wears, which the summon spells take as reagents.

  The summoned lord stands still for eight seconds: it turns to its summoner
  after a second and a half, denounces them, then becomes attackable and
  attacks them. It leaves a minute later unless it is fighting, and its corpse
  stays to be looted.
  """

  @behaviour ThistleTea.Game.Core.AI.GameObjectScript

  alias ThistleTea.Game.Core.AI.GameObjectScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @lesser_wind_stones [180_456, 180_518, 180_529, 180_544, 180_549, 180_564]
  @wind_stones [180_461, 180_534, 180_554]
  @greater_wind_stones [180_466, 180_539, 180_559]

  @crimson_templar 15_209
  @azure_templar 15_211
  @hoary_templar 15_212
  @earthen_templar 15_307
  @duke_of_cynders 15_206
  @duke_of_fathoms 15_207
  @duke_of_shards 15_208
  @duke_of_zephyrs 15_220
  @prince_skaldrenox 15_203
  @high_marshal_whirlaxis 15_204
  @baron_kazum 15_205
  @lord_skwol 15_305

  @templars [@crimson_templar, @azure_templar, @hoary_templar, @earthen_templar]
  @dukes [@duke_of_cynders, @duke_of_fathoms, @duke_of_shards, @duke_of_zephyrs]
  @royals [@prince_skaldrenox, @high_marshal_whirlaxis, @baron_kazum, @lord_skwol]

  @summons %{
    24_734 => @templars,
    24_744 => [@crimson_templar],
    24_756 => [@hoary_templar],
    24_758 => [@earthen_templar],
    24_760 => [@azure_templar],
    24_763 => @dukes,
    24_765 => [@duke_of_cynders],
    24_768 => [@duke_of_zephyrs],
    24_770 => [@duke_of_shards],
    24_772 => [@duke_of_fathoms],
    24_784 => @royals,
    24_786 => [@prince_skaldrenox],
    24_788 => [@high_marshal_whirlaxis],
    24_789 => [@baron_kazum],
    24_790 => [@lord_skwol]
  }

  @templar_texts [10_686, 10_694, 10_695, 10_696]
  @duke_texts [10_801, 10_802, 10_803, 10_804]
  @royal_texts [10_805, 10_806, 10_807, 10_810]

  @summon_positions %{
    180_461 => {-7_927.48, 1_935.30, 5.61, 4.76475},
    180_534 => {-6_998.52, 1_223.02, 9.16, 4.76475},
    180_554 => {-6_716.82, 1_674.36, 8.51, 4.76475}
  }

  @despawn_ms 60_000
  @timed_or_dead_despawn 1
  @no_attack -1
  @challenge_script 1
  @one_in_four 25
  @despawn_stone 15

  @turn_ms 1_500
  @talk_ms 1_600
  @attack_ms 8_000
  @unit_flags 46
  @immune_to_player 0x100
  @remove_flags 2

  @impl GameObjectScript
  def entries, do: @lesser_wind_stones ++ @wind_stones ++ @greater_wind_stones

  @impl GameObjectScript
  def spells, do: Map.keys(@summons)

  @impl GameObjectScript
  def activated(entry, spell_id, position) do
    position = Map.get(@summon_positions, entry, position)
    {summon(Map.fetch!(@summons, spell_id), position), @despawn_stone}
  end

  defp summon([entry], position), do: [lord(entry, position)]

  defp summon([first, second, third, fourth], position) do
    [
      %ScriptStep{
        command: :start_script,
        datalong: 1,
        dataint: @one_in_four,
        datalong2: 2,
        dataint2: @one_in_four,
        datalong3: 3,
        dataint3: @one_in_four,
        datalong4: 4,
        dataint4: @one_in_four,
        sub_scripts: %{
          1 => [lord(first, position)],
          2 => [lord(second, position)],
          3 => [lord(third, position)],
          4 => [lord(fourth, position)]
        }
      }
    ]
  end

  defp lord(entry, position) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: @despawn_ms,
      dataint2: @challenge_script,
      dataint3: @no_attack,
      dataint4: @timed_or_dead_despawn,
      position: position,
      sub_scripts: %{@challenge_script => challenge(texts(entry))}
    }
  end

  defp challenge([first, second, third, fourth]) do
    [
      %ScriptStep{command: :turn_to, datalong: 0, delay_ms: @turn_ms},
      %ScriptStep{
        command: :talk,
        dataint: first,
        dataint2: second,
        dataint3: third,
        dataint4: fourth,
        delay_ms: @talk_ms
      },
      %ScriptStep{
        command: :modify_flags,
        datalong: @unit_flags,
        datalong2: @immune_to_player,
        datalong3: @remove_flags,
        delay_ms: @attack_ms
      },
      %ScriptStep{command: :attack_start, delay_ms: @attack_ms}
    ]
  end

  defp texts(entry) when entry in @templars, do: @templar_texts
  defp texts(entry) when entry in @dukes, do: @duke_texts
  defp texts(entry) when entry in @royals, do: @royal_texts
end
