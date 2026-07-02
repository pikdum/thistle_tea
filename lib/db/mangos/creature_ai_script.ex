defmodule ThistleTea.DB.Mangos.CreatureAiScript do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Query

  alias ThistleTea.DB.Mangos

  @command_cast_spell 15
  @command_add_aura 44
  @target_provided 0
  @data_flag_target_self 0x04

  @primary_key false
  schema "creature_ai_scripts" do
    field(:id, :integer)
    field(:delay, :integer, default: 0)
    field(:priority, :integer, default: 0)
    field(:command, :integer, default: 0)
    field(:datalong, :integer, default: 0)
    field(:target_type, :integer, default: 0)
    field(:data_flags, :integer, default: 0)
    field(:condition_id, :integer, default: 0)
  end

  def spawn_self_aura_spell_ids([]), do: []

  def spawn_self_aura_spell_ids(ids) do
    ids
    |> query_spawn_self_auras()
    |> Mangos.Repo.all()
    |> Enum.map(& &1.datalong)
  end

  defp query_spawn_self_auras(ids) do
    from(s in __MODULE__,
      where: s.id in ^ids,
      where: s.condition_id == 0,
      where: s.delay == 0,
      where: s.command in [@command_cast_spell, @command_add_aura],
      where: s.target_type == @target_provided,
      where: fragment("? & ?", s.data_flags, ^@data_flag_target_self) != 0,
      where: s.datalong > 0,
      order_by: [s.id, s.delay, s.priority]
    )
  end
end
