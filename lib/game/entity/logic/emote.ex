defmodule ThistleTea.Game.Entity.Logic.Emote do
  @moduledoc """
  Pure animation and posture transitions, including animation-interrupted auras
  and channels. Text emotes leave client-controlled sitting poses to posture requests.
  """

  import Bitwise, only: [band: 2]

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Emote
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell.Cast

  @prevent_animation 0x20000000
  @animation_interrupt 0x20
  @client_postures [0, 1, 3, 8]
  @text_only_animations [0, 12, 13, 68]

  def allowed?(entity), do: Death.alive?(entity) and posture_allowed?(entity)

  def command(entity, id, now) when id in [0, 3] do
    if allowed?(entity) do
      entity = interrupt(entity, now)
      entity = if id == 0, do: set_state(entity, 0), else: entity
      Effects.enqueue(entity, %Effects.EmoteAnimation{emote_id: id})
    else
      entity
    end
  end

  def command(entity, _id, _now), do: entity

  def text(entity, %Emote{id: id} = emote, now) do
    if allowed?(entity) and id not in @text_only_animations do
      entity |> interrupt(now) |> play(emote)
    else
      entity
    end
  end

  def play(entity, %Emote{} = emote), do: Effects.enqueue(entity, animation_effect(emote))

  def animation_effect(%Emote{id: id, persistent?: persistent?}) when persistent? or id == 0,
    do: %Effects.EmoteState{emote_id: id}

  def animation_effect(%Emote{id: id}), do: %Effects.EmoteAnimation{emote_id: id}

  def stand(entity, posture, now) when posture in @client_postures do
    if posture_allowed?(entity), do: entity |> interrupt(now) |> set_posture(posture, now), else: entity
  end

  def stand(entity, _posture, _now), do: entity

  def move(entity, moved?, moving_or_turning?, now) do
    entity = if moved?, do: set_state(entity, 0), else: entity
    if moving_or_turning?, do: set_posture(entity, 0, now), else: entity
  end

  def reset(%{unit: %Unit{} = unit} = entity) do
    if unit.npc_emote_state in [nil, 0] and unit.stand_state in [nil, 0] do
      entity
    else
      %{entity | unit: %{unit | npc_emote_state: 0, stand_state: 0}} |> Core.mark_broadcast_update()
    end
  end

  def set_state(%{unit: %Unit{npc_emote_state: current}} = entity, id) when current == id, do: entity

  def set_state(%{unit: %Unit{} = unit} = entity, id) do
    %{entity | unit: %{unit | npc_emote_state: id}} |> Core.mark_broadcast_update()
  end

  defp posture_allowed?(%{unit: %Unit{flags: flags}}), do: band(flags || 0, @prevent_animation) == 0

  defp set_posture(%{unit: %Unit{stand_state: posture}} = entity, posture, _now), do: entity

  defp set_posture(%{unit: %Unit{} = unit} = entity, posture, now) do
    entity = %{entity | unit: %{unit | stand_state: posture}}
    entity = if posture == 0, do: remove_auras(entity, Aura.interrupt_mask(:stand), now), else: entity

    entity
    |> Core.mark_broadcast_update()
    |> Effects.enqueue(Effects.stand_state(posture))
  end

  defp interrupt(entity, now) do
    entity
    |> interrupt_channel(now)
    |> remove_auras(@animation_interrupt, now)
  end

  defp interrupt_channel(%{internal: %{casting: %Cast{spell: spell} = cast}} = entity, now) do
    if Cast.channeled?(cast) and band(spell.channel_interrupt_flags, @animation_interrupt) != 0,
      do: Casting.cancel(entity, now),
      else: entity
  end

  defp interrupt_channel(entity, _now), do: entity

  defp remove_auras(entity, mask, now) do
    {entity, events} = Aura.remove_with_interrupt_flags(entity, mask, now)
    Effects.enqueue(entity, events)
  end
end
