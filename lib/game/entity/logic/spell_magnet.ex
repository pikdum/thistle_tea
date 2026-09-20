defmodule ThistleTea.Game.Entity.Logic.SpellMagnet do
  @moduledoc """
  Spell-magnet eligibility and aura lifecycle projections. A source's charge
  is shared by all recipients of its area aura.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Spell

  def eligible?(%Spell{} = spell) do
    (spell.dmg_class == 1 or spell.spell_visual == 7250) and spell.dispel_type != 4 and
      Spell.harmful?(spell) and not SpellTarget.area_targeted?(spell) and
      not Enum.any?([:ability, :no_redirection, :suppress_target_procs, :passive], &Spell.attribute?(spell, &1))
  end

  def events(previous, current) do
    before = projection(previous)
    after_projection = projection(current)

    if before == after_projection do
      []
    else
      [%Effects.SpellMagnetsChanged{magnets: after_projection}]
    end
  end

  defp projection(holders) do
    for %Holder{} = holder <- holders,
        Holder.has_aura_type?(holder, :spell_magnet) do
      %{
        source_guid: holder.caster_guid,
        spell_id: holder.spell.id,
        applied_at: holder.applied_at,
        expires_at: holder.expires_at,
        charges: holder.charges,
        radius: holder.area_radius
      }
    end
  end
end
