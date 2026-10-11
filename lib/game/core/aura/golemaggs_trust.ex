defmodule ThistleTea.Game.Core.Aura.GolemaggsTrust do
  @moduledoc "Golemagg's living, engaged caster refreshes nearby Core Ragers every second."

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect

  @aura 20_556
  @buff 20_553
  @core_rager 11_672

  def spell?(%Spell{id: @aura}), do: true
  def spell?(_spell), do: false

  def interval(%Spell{id: @aura}, %Effect{index: 0, aura: type}) when type in [:dummy, :periodic_trigger_spell],
    do: 1_000

  def interval(_spell, _effect), do: nil

  def tick_events(
        %{object: %{guid: guid}, unit: %Unit{health: health}, internal: %Internal{in_combat: true}},
        %Holder{spell: %Spell{id: @aura}, caster_guid: guid},
        %Aura{index: 0}
      )
      when is_integer(health) and health > 0 do
    [
      %Effects.TriggerCreatureSpellInRange{
        spell_id: @buff,
        creature_entry: @core_rager,
        radius: 30.0,
        triggering_spell_id: @aura
      }
    ]
  end

  def tick_events(_entity, _holder, _aura), do: []
end
