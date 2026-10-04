defmodule ThistleTea.Game.Core.InstanceScript.Maraudon do
  @moduledoc """
  Celebras the Redeemed's appearance in Maraudon, after vmangos
  `instance_maraudon`.

  The redeemed spirit stands beside Celebras the Cursed but stays hidden
  until the cursed form falls, then offers The Scepter of Celebras
  (`QuestEscort.Catalog`). The larva spewer encounter is not ported.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.InstanceScript.Encounter

  @celebras 1
  @done 3

  @celebras_the_cursed 12_225
  @celebras_the_redeemed 13_716

  def broadcast_text_ids, do: []
  def summon_entries, do: []
  def game_object_db_guids, do: []
  def registered_fields, do: [@celebras]
  def door_entries, do: []
  def data64(_index), do: nil
  def initial_value(_field), do: 0

  def set_data(data, @celebras, value) do
    stored = Encounter.settle(data, @celebras, value)
    reveal = if stored == @done and not Encounter.done?(data, @celebras), do: [conceal_redeemed(false, nil)], else: []
    {:ok, stored, Map.put(data, @celebras, stored), reveal}
  end

  def set_data(data, field, value) do
    stored = Encounter.settle(data, field, value)
    {:ok, stored, Map.put(data, field, stored), []}
  end

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}

  def game_object_spawned(_data, _script_state, _entry), do: {:ok, []}

  def creature_event(data, script_state, %{creature_entry: @celebras_the_cursed, event: :death}) do
    {:ok, _stored, data, effects} = set_data(data, @celebras, @done)
    {:ok, data, script_state, effects}
  end

  def creature_event(data, script_state, %{creature_entry: @celebras_the_redeemed, event: :spawned, creature_guid: guid}) do
    effects = if Encounter.done?(data, @celebras), do: [], else: [conceal_redeemed(true, guid)]
    {:ok, data, script_state, effects}
  end

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp conceal_redeemed(concealed?, guid) do
    %Effects.RunCreatureScript{
      creature_entry: @celebras_the_redeemed,
      creature_guid: guid,
      steps: [%ScriptStep{command: :set_concealed, datalong: if(concealed?, do: 1, else: 0)}]
    }
  end
end
