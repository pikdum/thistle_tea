defmodule ThistleTea.DB.Mangos.CreatureAiEvent do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Query

  alias ThistleTea.DB.Mangos

  @event_timer_ooc 1
  @event_spawned 11

  @primary_key {:id, :integer, autogenerate: false}
  schema "creature_ai_events" do
    field(:creature_id, :integer)
    field(:condition_id, :integer, default: 0)
    field(:event_type, :integer, default: 0)
    field(:event_chance, :integer, default: 100)
    field(:event_param1, :integer, default: 0)
    field(:event_param2, :integer, default: 0)
    field(:action1_script, :integer, default: 0)
    field(:action2_script, :integer, default: 0)
    field(:action3_script, :integer, default: 0)
  end

  def spawn_aura_query(entry) do
    from(e in __MODULE__,
      where: e.creature_id == ^entry,
      where: e.condition_id == 0,
      where: e.event_chance == 100,
      where:
        e.event_type == @event_spawned or
          (e.event_type == @event_timer_ooc and e.event_param1 <= 1_000 and e.event_param2 <= 1_000),
      select: [e.action1_script, e.action2_script, e.action3_script]
    )
  end

  def spawn_aura_script_ids(entry) do
    entry
    |> spawn_aura_query()
    |> Mangos.Repo.all()
    |> List.flatten()
    |> Enum.filter(&(&1 > 0))
  end
end
