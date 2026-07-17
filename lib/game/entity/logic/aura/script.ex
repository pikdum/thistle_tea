defmodule ThistleTea.Game.Entity.Logic.Aura.Script do
  @moduledoc """
  Interprets aura lifecycle behavior that VMangos marks with an explicit
  `spell_template.script_name` because the spell data cannot express it.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell

  @wyvern_sting_poison_by_rank %{19_386 => 24_131, 24_132 => 24_134, 24_133 => 24_135}

  def after_remove(entity, holders) when is_list(holders) do
    Enum.flat_map(holders, &after_remove_holder(entity, &1))
  end

  defp after_remove_holder(%{object: %{guid: target_guid}}, %Holder{
         spell: %Spell{id: spell_id} = spell,
         caster_guid: caster_guid,
         caster_level: caster_level
       })
       when is_integer(caster_guid) and is_integer(target_guid) do
    case {spell.script_name, @wyvern_sting_poison_by_rank[spell_id]} do
      {"spell_hunter_wyvern_sting", poison_id} when is_integer(poison_id) ->
        [Event.trigger_spell(caster_guid, caster_level, target_guid, poison_id)]

      _other ->
        []
    end
  end

  defp after_remove_holder(_entity, _holder), do: []
end
