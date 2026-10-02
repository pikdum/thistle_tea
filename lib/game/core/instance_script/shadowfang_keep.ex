defmodule ThistleTea.Game.Core.InstanceScript.ShadowfangKeep do
  @moduledoc """
  Shadowfang Keep's sealed doors, after vmangos `instance_shadowfang_keep`.

  Freeing Sorcerer Ashcrombe or Deathstalker Adamant opens the Courtyard Door,
  the fourth of the voidwalkers Arugal raises over Fenrus' corpse opens the
  Sorcerer's Gate, and Wolf Master Nandos' death opens Arugal's Lair. The world
  database's creature scripts report each step.

  A gate that spawns again follows the voidwalkers rather than Fenrus, who dies
  before they are raised.
  """

  alias ThistleTea.Game.Core.InstanceScript.Doors
  alias ThistleTea.Game.Core.InstanceScript.Encounter

  @free_npc 1
  @rethilgore 2
  @fenrus 3
  @nandos 4
  @intro 5
  @voidwalkers 6

  @done 3
  @voidwalkers_to_open 4

  @courtyard_door 18_895
  @arugals_lair 18_971
  @sorcerers_gate 18_972

  def broadcast_text_ids, do: []
  def summon_entries, do: []
  def game_object_db_guids, do: []
  def registered_fields, do: [@free_npc, @rethilgore, @fenrus, @nandos, @intro, @voidwalkers]
  def door_entries, do: Enum.map(doors(), &elem(&1, 0))
  def data64(_index), do: nil
  def initial_value(_field), do: 0

  def set_data(data, @voidwalkers, @done),
    do: Doors.put(doors(), data, @voidwalkers, Encounter.value(data, @voidwalkers) + 1)

  def set_data(data, @voidwalkers, _value), do: {:ok, Encounter.value(data, @voidwalkers), data, []}
  def set_data(data, field, value), do: Doors.put(doors(), data, field, Encounter.settle(data, field, value))

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}

  def game_object_spawned(data, _script_state, entry), do: {:ok, Doors.spawned(doors(), data, %{}, entry)}

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp doors do
    [
      {@courtyard_door, &Encounter.done?(&1, @free_npc)},
      {@sorcerers_gate, &(Encounter.value(&1, @voidwalkers) >= @voidwalkers_to_open)},
      {@arugals_lair, &Encounter.done?(&1, @nandos)}
    ]
  end
end
