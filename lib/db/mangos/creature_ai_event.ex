defmodule ThistleTea.DB.Mangos.CreatureAiEvent do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Query

  @primary_key {:id, :integer, autogenerate: false}
  schema "creature_ai_events" do
    field(:creature_id, :integer)
    field(:condition_id, :integer, default: 0)
    field(:event_type, :integer, default: 0)
    field(:event_inverse_phase_mask, :integer, default: 0)
    field(:event_chance, :integer, default: 100)
    field(:event_flags, :integer, default: 0)
    field(:event_param1, :integer, default: 0)
    field(:event_param2, :integer, default: 0)
    field(:event_param3, :integer, default: 0)
    field(:event_param4, :integer, default: 0)
    field(:action1_script, :integer, default: 0)
    field(:action2_script, :integer, default: 0)
    field(:action3_script, :integer, default: 0)
  end

  def query(creature_id) do
    from(e in __MODULE__,
      where: e.creature_id == ^creature_id,
      order_by: e.id
    )
  end

  def action_script_ids(%__MODULE__{action1_script: a1, action2_script: a2, action3_script: a3}) do
    Enum.filter([a1, a2, a3], &(is_integer(&1) and &1 > 0))
  end
end
