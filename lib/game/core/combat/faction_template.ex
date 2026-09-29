defmodule ThistleTea.Game.Core.Combat.FactionTemplate do
  @moduledoc """
  Faction template reactions: which factions and faction groups a template
  treats as friends or enemies, and its call-for-help and contested-territory
  flags. `World.Loader.Faction` builds these from `FactionTemplate.dbc` rows.
  """

  import Bitwise, only: [&&&: 2]

  defstruct id: nil,
            faction: 0,
            flags: 0,
            faction_group: 0,
            friend_group: 0,
            enemy_group: 0,
            enemies_0: 0,
            enemies_1: 0,
            enemies_2: 0,
            enemies_3: 0,
            friends_0: 0,
            friends_1: 0,
            friends_2: 0,
            friends_3: 0

  @flag_respond_to_call_for_help 0x01
  @flag_flee_from_call_for_help 0x400
  @flag_attack_contested_players 0x1000

  @fields [
    :id,
    :faction,
    :flags,
    :faction_group,
    :friend_group,
    :enemy_group,
    :enemies_0,
    :enemies_1,
    :enemies_2,
    :enemies_3,
    :friends_0,
    :friends_1,
    :friends_2,
    :friends_3
  ]

  def from_row(nil), do: nil
  def from_row(row), do: struct(__MODULE__, Map.take(row, @fields))

  def responds_to_call_for_help?(%__MODULE__{flags: flags}) when is_integer(flags) do
    (flags &&& @flag_respond_to_call_for_help) != 0 and (flags &&& @flag_flee_from_call_for_help) == 0
  end

  def responds_to_call_for_help?(_faction_template), do: false

  def flees_from_call_for_help?(%__MODULE__{flags: flags}) when is_integer(flags),
    do: (flags &&& @flag_flee_from_call_for_help) != 0

  def flees_from_call_for_help?(_faction_template), do: false

  def attacks_contested_players?(%__MODULE__{flags: flags}) when is_integer(flags) do
    (flags &&& @flag_attack_contested_players) != 0
  end

  def attacks_contested_players?(_faction_template), do: false

  def friendly_to?(%__MODULE__{} = source, %__MODULE__{} = target) do
    cond do
      enemy_faction?(source, target.faction) -> false
      friend_faction?(source, target.faction) -> true
      true -> (source.friend_group &&& target.faction_group) != 0 or (source.faction_group &&& target.friend_group) != 0
    end
  end

  def friendly_to?(_source, _target), do: false

  def hostile_to?(%__MODULE__{} = source, %__MODULE__{} = target) do
    cond do
      enemy_faction?(source, target.faction) -> true
      friend_faction?(source, target.faction) -> false
      true -> (source.enemy_group &&& target.faction_group) != 0
    end
  end

  def hostile_to?(_source, _target), do: false

  def neutral_to_all?(%__MODULE__{} = faction_template) do
    not listed_any?(
      faction_template.enemies_0,
      faction_template.enemies_1,
      faction_template.enemies_2,
      faction_template.enemies_3
    ) and
      faction_template.enemy_group == 0 and faction_template.friend_group == 0
  end

  def neutral_to_all?(_faction_template), do: true

  defp enemy_faction?(%__MODULE__{} = source, faction),
    do: listed?(faction, source.enemies_0, source.enemies_1, source.enemies_2, source.enemies_3)

  defp friend_faction?(%__MODULE__{} = source, faction),
    do: listed?(faction, source.friends_0, source.friends_1, source.friends_2, source.friends_3)

  defp listed?(faction, a, b, c, d) when is_integer(faction) and faction != 0,
    do: faction === a or faction === b or faction === c or faction === d

  defp listed?(_faction, _a, _b, _c, _d), do: false

  defp listed_any?(a, b, c, d), do: nonzero?(a) or nonzero?(b) or nonzero?(c) or nonzero?(d)

  defp nonzero?(value), do: is_integer(value) and value != 0
end
