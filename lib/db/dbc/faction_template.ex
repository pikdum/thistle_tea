defmodule FactionTemplate do
  @moduledoc false

  use Ecto.Schema

  import Bitwise, only: [&&&: 2]

  @primary_key {:id, :integer, autogenerate: false}
  schema "FactionTemplate" do
    field(:faction, :integer, default: 0)
    field(:flags, :integer, default: 0)
    field(:faction_group, :integer, default: 0)
    field(:friend_group, :integer, default: 0)
    field(:enemy_group, :integer, default: 0)
    field(:enemies_0, :integer, default: 0)
    field(:enemies_1, :integer, default: 0)
    field(:enemies_2, :integer, default: 0)
    field(:enemies_3, :integer, default: 0)
    field(:friends_0, :integer, default: 0)
    field(:friends_1, :integer, default: 0)
    field(:friends_2, :integer, default: 0)
    field(:friends_3, :integer, default: 0)
  end

  @flag_respond_to_call_for_help 0x01
  @flag_flee_from_call_for_help 0x400

  def responds_to_call_for_help?(%__MODULE__{flags: flags}) when is_integer(flags) do
    (flags &&& @flag_respond_to_call_for_help) != 0 and (flags &&& @flag_flee_from_call_for_help) == 0
  end

  def responds_to_call_for_help?(_faction_template), do: false

  def friendly_to?(%__MODULE__{} = source, %__MODULE__{} = target) do
    cond do
      target.faction in enemy_factions(source) -> false
      target.faction in friend_factions(source) -> true
      true -> (source.friend_group &&& target.faction_group) != 0 or (source.faction_group &&& target.friend_group) != 0
    end
  end

  def friendly_to?(_source, _target), do: false

  def hostile_to?(%__MODULE__{} = source, %__MODULE__{} = target) do
    cond do
      target.faction in enemy_factions(source) -> true
      target.faction in friend_factions(source) -> false
      true -> (source.enemy_group &&& target.faction_group) != 0
    end
  end

  def hostile_to?(_source, _target), do: false

  def neutral_to_all?(%__MODULE__{} = faction_template) do
    enemy_factions(faction_template) == [] and faction_template.enemy_group == 0 and faction_template.friend_group == 0
  end

  def neutral_to_all?(_faction_template), do: true

  defp enemy_factions(%__MODULE__{} = faction_template) do
    faction_template
    |> faction_values([:enemies_0, :enemies_1, :enemies_2, :enemies_3])
  end

  defp friend_factions(%__MODULE__{} = faction_template) do
    faction_template
    |> faction_values([:friends_0, :friends_1, :friends_2, :friends_3])
  end

  defp faction_values(%__MODULE__{} = faction_template, keys) do
    keys
    |> Enum.map(&Map.get(faction_template, &1))
    |> Enum.filter(&is_integer/1)
    |> Enum.reject(&(&1 == 0))
  end
end
