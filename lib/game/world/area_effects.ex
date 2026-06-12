defmodule ThistleTea.Game.World.AreaEffects do
  @moduledoc """
  Duplicate-key registry of live area-effect dynamic objects keyed by
  `{caster_guid, spell_id}`. Each `DynamicObject` process registers itself on
  init and the Registry unregisters it on exit, so casters can despawn their
  own effects without tracking guids on the entity.
  """
  def child_spec(_opts) do
    Registry.child_spec(keys: :duplicate, name: __MODULE__)
  end

  def register(caster_guid, spell_id) when is_integer(caster_guid) and is_integer(spell_id) do
    Registry.register(__MODULE__, {caster_guid, spell_id}, nil)
  end

  def register(_caster_guid, _spell_id), do: {:error, :invalid_key}

  def pids(caster_guid, spell_id) do
    __MODULE__
    |> Registry.lookup({caster_guid, spell_id})
    |> Enum.map(fn {pid, _value} -> pid end)
  end
end
