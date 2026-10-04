defmodule ThistleTea.Game.Core.InstanceScript.WailingCaverns do
  @moduledoc """
  The Fanglords and Naralex's nightmare in Wailing Caverns, after vmangos
  `instance_wailing_caverns`.

  Each Fanglord reports its fight to the copy. Lord Serpentis cries out when
  the first of Anacondra, Cobrahn, and Pythas falls, and once all four lie
  dead the Disciple of Naralex calls the party to him, ready to lead the
  ritual (`CreatureScript.WailingCaverns`). While Lady Anacondra rests she
  dismisses the Druid of the Fang standing at her side. When Mutanus the
  Devourer dies the nightmare ends and every living creature it holds in the
  caverns vanishes, sparing the critters, Kresh, and the two druids.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.InstanceScript.Encounter

  @anacondra_field 0
  @cobrahn_field 1
  @pythas_field 2
  @serpentis_field 3
  @disciple_field 4
  @mutanus_field 5
  @fanglords [@anacondra_field, @cobrahn_field, @pythas_field, @serpentis_field]

  @not_started 0
  @done 3
  @special 4
  @assaulted :serpentis_warned

  @anacondra 3_671
  @serpentis 3_673
  @disciple 3_678
  @druid_of_the_fang 3_840
  @yell_after_fanglords 2_101
  @serpentis_yell 2_102
  @interaction_reach 5

  @nightmare_creatures [
    3_636,
    3_637,
    3_640,
    3_654,
    3_669,
    3_670,
    3_671,
    3_673,
    3_674,
    3_840,
    5_048,
    5_053,
    5_055,
    5_056,
    5_755,
    5_756,
    5_761,
    5_762,
    5_763,
    5_775,
    5_912,
    8_886
  ]

  def broadcast_text_ids, do: [@yell_after_fanglords, @serpentis_yell]
  def summon_entries, do: []
  def game_object_db_guids, do: []
  def registered_fields, do: @fanglords ++ [@disciple_field, @mutanus_field]
  def door_entries, do: []
  def data64(_index), do: nil
  def initial_value(_field), do: @not_started

  def disciple_field, do: @disciple_field
  def mutanus_field, do: @mutanus_field
  def special, do: @special

  def set_data(data, field, value) do
    stored = Encounter.settle(data, field, value)
    data = Map.put(data, field, stored)
    {data, effects} = react(data, field, stored)
    {data, ready} = call_party(data)
    {:ok, stored, data, effects ++ ready}
  end

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}
  def game_object_spawned(_data, _script_state, _entry), do: {:ok, []}
  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}
  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp react(data, @anacondra_field, @special), do: {data, [dismiss_druid()]}

  defp react(data, field, @done) when field in [@anacondra_field, @cobrahn_field, @pythas_field] do
    if Map.get(data, @assaulted, false),
      do: {data, []},
      else: {Map.put(data, @assaulted, true), [talk(@serpentis, @serpentis_yell)]}
  end

  defp react(data, @mutanus_field, @done), do: {data, Enum.map(@nightmare_creatures, &vanish/1)}
  defp react(data, _field, _value), do: {data, []}

  defp call_party(data) do
    if Enum.all?(@fanglords, &Encounter.done?(data, &1)) and Encounter.value(data, @disciple_field) == @not_started,
      do: {Map.put(data, @disciple_field, @special), [talk(@disciple, @yell_after_fanglords)]},
      else: {data, []}
  end

  defp dismiss_druid do
    %Effects.RunCreatureScript{
      creature_entry: @anacondra,
      steps: [
        %ScriptStep{
          command: :despawn,
          target_type: :nearest_creature_with_entry,
          target_param1: @druid_of_the_fang,
          target_param2: @interaction_reach,
          condition: alive()
        }
      ]
    }
  end

  defp talk(entry, text_id), do: %Effects.MonsterTalk{creature_entry: entry, broadcast_text_id: text_id}

  defp vanish(entry) do
    %Effects.RunCreatureScript{creature_entry: entry, steps: [%ScriptStep{command: :despawn, condition: alive()}]}
  end

  defp alive, do: %Condition{type: :alive}
end
