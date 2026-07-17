defmodule ThistleTea.DB.Mangos.SpellScript do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Query

  @primary_key false
  schema "spell_scripts" do
    field(:id, :integer)
    field(:delay, :integer, default: 0)
    field(:priority, :integer, default: 0)
    field(:command, :integer, default: 0)
    field(:datalong, :integer, default: 0)
    field(:datalong2, :integer, default: 0)
    field(:datalong3, :integer, default: 0)
    field(:datalong4, :integer, default: 0)
    field(:target_param1, :integer, default: 0)
    field(:target_param2, :integer, default: 0)
    field(:target_type, :integer, default: 0)
    field(:data_flags, :integer, default: 0)
    field(:dataint, :integer, default: 0)
    field(:dataint2, :integer, default: 0)
    field(:dataint3, :integer, default: 0)
    field(:dataint4, :integer, default: 0)
    field(:x, :float, default: 0.0)
    field(:y, :float, default: 0.0)
    field(:z, :float, default: 0.0)
    field(:o, :float, default: 0.0)
    field(:condition_id, :integer, default: 0)
  end

  def query(script_ids) when is_list(script_ids) do
    from(s in __MODULE__, where: s.id in ^script_ids, order_by: [s.id, s.delay, s.priority])
  end
end
