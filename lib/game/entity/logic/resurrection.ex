defmodule ThistleTea.Game.Entity.Logic.Resurrection do
  @moduledoc "Pure offer selection and travel acknowledgement state for spell resurrection."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.ResurrectionOffer
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext

  def offer(%Character{internal: %{pending_resurrect: nil}} = character, %CastContext{} = context, spell, health, mana) do
    if Death.alive?(character) do
      {character, []}
    else
      offer = %ResurrectionOffer{
        caster_guid: context.caster_guid,
        position: context.caster_position,
        orientation: context.caster_orientation,
        health: health,
        mana: mana
      }

      delayed? = not Spell.attribute?(spell, :no_resurrection_timer)
      {put(character, offer), [Effects.resurrect_request(context.caster_guid, spell.id, health, mana, delayed?)]}
    end
  end

  def offer(character, _context, _spell, _health, _mana), do: {character, []}

  def respond(%Character{} = character, guid, status) do
    if Death.alive?(character), do: character, else: respond_to_offer(character, guid, status)
  end

  defp respond_to_offer(character, _guid, 0), do: clear(character)

  defp respond_to_offer(
         %Character{internal: %{pending_resurrect: %ResurrectionOffer{caster_guid: guid, phase: :offered} = offer}} =
           character,
         guid,
         1
       ) do
    put(character, %{offer | phase: :accepted})
  end

  defp respond_to_offer(character, _guid, _status), do: character

  def expect_arrival(
        %Character{internal: %{pending_resurrect: %ResurrectionOffer{phase: :transferring, arrival: nil} = offer}} =
          character,
        arrival
      ) do
    put(character, %{offer | arrival: arrival})
  end

  def expect_arrival(character, _arrival), do: character

  def cancel_transfer(%Character{internal: %{pending_resurrect: %ResurrectionOffer{phase: phase}}} = character)
      when phase != :offered, do: clear(character)

  def cancel_transfer(character), do: character

  def clear(%Character{} = character), do: put(character, nil)
  def clear(entity), do: entity

  def put(%Character{internal: internal} = character, offer),
    do: %{character | internal: %{internal | pending_resurrect: offer}}
end
