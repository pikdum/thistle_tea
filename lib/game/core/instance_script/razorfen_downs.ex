defmodule ThistleTea.Game.Core.InstanceScript.RazorfenDowns do
  @moduledoc """
  The gong of Razorfen Downs and the idol's fires, after vmangos
  `instance_razorfen_downs`.

  Striking the gong brings the dead: first eight Tomb Fiends, then four Tomb
  Reavers, then Tuten'kash himself, all running in from the two tunnels to
  the gong. Each fiend and reaver counts its death toward the gong waves
  (their EventAI raises the count), and the gong falls silent until the last
  of a wave is dead. Once the idol is shut down (`QuestEscort` for
  Belnistrasz) its oven, mouth, and cup fires go out.

  Unlike vmangos, the summons appear at fixed spots around each tunnel mouth
  instead of random ones, and only scatter on their way to the gong.
  """

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.InstanceScript.Encounter

  @tuten_kash_field 0
  @gong_waves_field 1
  @extinguish_fires_field 2

  @gong 148_917
  @tomb_fiend 7_349
  @tomb_reaver 7_351
  @tuten_kash 7_355

  @fiend_wave 1
  @fiends_slain 9
  @reaver_wave 10
  @reavers_slain 14
  @tuten_kash_wave 15

  @idol_fires [32_027, 32_029, 32_030, 32_031]

  @west_tunnel {2502.635, 844.140, 46.896, 0.633}
  @north_tunnel {2546.33, 887.455, 47.69, 0.633}
  @gong_approach {2533.479, 870.020, 47.678}
  @approach_scatter 5.0
  @offsets [{0.0, 0.0}, {3.0, -2.0}, {-2.0, 3.0}, {-4.0, -3.0}, {4.0, 3.0}]
  @random_point 3
  @pathfind_run 0x1 ||| 0x4
  @dead_despawn 7

  def broadcast_text_ids, do: []
  def summon_entries, do: [@tomb_fiend, @tomb_reaver, @tuten_kash]
  def game_object_db_guids, do: []
  def registered_fields, do: [@tuten_kash_field, @gong_waves_field, @extinguish_fires_field]
  def door_entries, do: []
  def data64(_index), do: nil
  def initial_value(_field), do: 0

  def set_data(data, @gong_waves_field, value) do
    {:ok, value, Map.put(data, @gong_waves_field, value), gong_wave(value)}
  end

  def set_data(data, @extinguish_fires_field, value) do
    effects = Enum.map(@idol_fires, &%Effects.SuspendGameObject{db_guid: &1})
    {:ok, value, Map.put(data, @extinguish_fires_field, value), effects}
  end

  def set_data(data, field, value) do
    stored = Encounter.settle(data, field, value)
    {:ok, stored, Map.put(data, field, stored), []}
  end

  def game_object_used(data, script_state, @gong) do
    {:ok, _stored, data, effects} = set_data(data, @gong_waves_field, Encounter.value(data, @gong_waves_field) + 1)
    {:ok, data, script_state, effects}
  end

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}

  def game_object_spawned(data, _script_state, @gong) do
    if Encounter.done?(data, @tuten_kash_field) or Encounter.value(data, @gong_waves_field) >= @tuten_kash_wave,
      do: {:ok, [gong(:inert)]},
      else: {:ok, []}
  end

  def game_object_spawned(_data, _script_state, _entry), do: {:ok, []}

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}
  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp gong_wave(wave) when wave in [@fiends_slain, @reavers_slain], do: [gong(:active)]
  defp gong_wave(@fiend_wave), do: [gong(:inert) | summon_wave(@tomb_fiend, 8)]
  defp gong_wave(@reaver_wave), do: [gong(:inert) | summon_wave(@tomb_reaver, 4)]
  defp gong_wave(@tuten_kash_wave), do: [gong(:inert) | summon_wave(@tuten_kash, 1)]
  defp gong_wave(_wave), do: []

  defp summon_wave(entry, count) do
    0..(count - 1)
    |> Enum.map(fn index ->
      tunnel = if rem(index, 2) == 0, do: @west_tunnel, else: @north_tunnel
      {dx, dy} = Enum.at(@offsets, rem(div(index, 2), length(@offsets)))
      {x, y, z, o} = tunnel

      %Effects.SummonCreature{
        entry: entry,
        position: {x + dx, y + dy, z, o},
        despawn_delay_ms: 0,
        despawn_type: @dead_despawn,
        steps: [approach_gong()]
      }
    end)
  end

  defp approach_gong do
    {x, y, z} = @gong_approach

    %ScriptStep{
      command: :move_to,
      datalong: @random_point,
      datalong3: @pathfind_run,
      position: {x, y, z, @approach_scatter}
    }
  end

  defp gong(action), do: %Effects.OperateGameObject{entry: @gong, action: action}
end
