defmodule ThistleTea.Game.Core.Spell.Holiday do
  @moduledoc """
  Holiday spell effects that vmangos scripts by spell id in `EffectDummy` and
  `EffectScriptEffect`, reached by the effect's target.

  Hallow's End: an innkeeper's Trick or Treat marks the player and either
  bags them a treat or tricks them into a random costume, the Hallowed Wands
  dress a friendly player who is out of combat in their costume, and Hallow's
  End Candy turns its eater into something random. Feast of Winter Veil: a
  snowball knocks down a party or raid member who has not grown resistant,
  mistletoe makes its target respond, Greatfather Winter's mistletoe gives
  mistletoe or holly, and a PX-238 Winter Wondervolt swaps the costume of
  whoever stands at its heart for a random one. A Bag of Heart Candies gives
  one of its candies. In the Lunar Festival, Elune's Candle sends one of its
  flames at Omen, a chosen flame at his minions, and a harmless spark at
  anything else.
  """

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Effects.RandomChoice
  alias ThistleTea.Game.Core.Effects.WhenGrouped
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext

  @trick_or_treat 24_751
  @tricked_or_treated 24_755
  @trick 24_714
  @treat 24_715
  @random_costume 24_720
  @hallows_end_candy 24_930
  @candy_transformations [24_924, 24_925, 24_926, 24_927]

  @wands %{24_717 => :pirate, 24_718 => :ninja, 24_719 => :leper_gnome, 24_737 => :ghost}
  @costumes %{
    pirate: {24_708, 24_709},
    ninja: {24_711, 24_710},
    leper_gnome: {24_712, 24_713},
    ghost: {24_735, 24_736},
    skeleton: 24_723,
    bat: 24_732,
    wisp: 24_740,
    critter: 24_753
  }
  @tricks [:pirate, :ninja, :leper_gnome, :ghost, :skeleton, :bat, :wisp, :critter]
  @wand_costumes [:pirate, :ninja, :leper_gnome, :skeleton, :bat, :ghost, :wisp]

  @snowball 21_343
  @snowball_knockdown 21_167
  @snowball_resistant 21_354
  @mistletoe 26_004
  @mistletoe_response 26_005
  @greatfather_mistletoe 26_218
  @mistletoe_gifts [26_206, 26_207]
  @wondervolt 26_275
  @wondervolt_costumes [26_272, 26_157, 26_273, 26_274]
  @wondervolt_reach 1.0
  @bag_of_candies 26_678
  @heart_candies [26_668, 26_670, 26_671, 26_672, 26_673, 26_674, 26_675, 26_676]
  @elunes_candle 26_374
  @candle_fizzle 26_636
  @omen 15_467
  @omen_candles [26_622, 26_623, 26_624, 26_625, 26_649]
  @minion_of_omen 15_466
  @minion_candle 26_624

  @spells [
            @trick_or_treat,
            @trick,
            @random_costume,
            @hallows_end_candy,
            @snowball,
            @mistletoe,
            @greatfather_mistletoe,
            @wondervolt,
            @bag_of_candies,
            @elunes_candle
          ] ++ Map.keys(@wands)

  def spell?(%Spell{id: id}), do: id in @spells
  def spell?(_spell), do: false

  def apply(%Character{} = state, %CastContext{}, %Spell{id: @trick_or_treat}, _now) do
    self_cast = &own_trigger(state, &1)
    {state, [self_cast.(@tricked_or_treated), pick([self_cast.(@trick), self_cast.(@treat)])]}
  end

  def apply(%Character{} = state, %CastContext{caster_guid: guid} = context, %Spell{id: @trick}, _now)
      when guid == state.object.guid do
    {state, [pick(Enum.map(@tricks, &trigger(context, guid, costume(&1, state))))]}
  end

  def apply(%Character{internal: %{in_combat: true}} = state, _context, %Spell{id: id}, _now)
      when id == @random_costume or is_map_key(@wands, id), do: {state, []}

  def apply(%Character{} = state, %CastContext{} = context, %Spell{id: @random_costume}, _now) do
    {state, [pick(Enum.map(@wand_costumes, &trigger(context, state.object.guid, costume(&1, state))))]}
  end

  def apply(%Character{} = state, %CastContext{} = context, %Spell{id: id}, _now) when is_map_key(@wands, id) do
    {state, [trigger(context, state.object.guid, costume(Map.fetch!(@wands, id), state))]}
  end

  def apply(state, %CastContext{caster_guid: guid} = context, %Spell{id: @hallows_end_candy}, _now)
      when guid == state.object.guid do
    {state, [pick(Enum.map(@candy_transformations, &trigger(context, guid, &1)))]}
  end

  def apply(%Character{} = state, %CastContext{caster_guid: caster} = context, %Spell{id: @snowball}, _now)
      when is_integer(caster) and caster != state.object.guid do
    if context.caster_type == :player and not Aura.has_spell?(state, @snowball_resistant),
      do:
        {state, [%WhenGrouped{guids: [caster, state.object.guid], effects: [own_trigger(state, @snowball_knockdown)]}]},
      else: {state, []}
  end

  def apply(state, %CastContext{}, %Spell{id: @mistletoe}, _now) do
    {state, [own_trigger(state, @mistletoe_response)]}
  end

  def apply(%Character{} = state, %CastContext{} = context, %Spell{id: @greatfather_mistletoe}, _now) do
    {state, [pick(Enum.map(@mistletoe_gifts, &trigger(context, state.object.guid, &1)))]}
  end

  def apply(state, %CastContext{} = context, %Spell{id: @wondervolt}, now) do
    if at_heart?(state, context) do
      {state, removed} = Aura.remove_spells(state, @wondervolt_costumes, now)
      {state, removed ++ [pick(Enum.map(@wondervolt_costumes, &own_trigger(state, &1)))]}
    else
      {state, []}
    end
  end

  def apply(state, %CastContext{caster_guid: guid} = context, %Spell{id: @bag_of_candies}, _now)
      when guid == state.object.guid do
    {state, [pick(Enum.map(@heart_candies, &trigger(context, guid, &1)))]}
  end

  def apply(
        %{object: %{guid: target, entry: entry}} = state,
        %CastContext{} = context,
        %Spell{id: @elunes_candle},
        _now
      ) do
    case entry do
      @omen -> {state, [pick(Enum.map(@omen_candles, &trigger(context, target, &1)))]}
      @minion_of_omen -> {state, [trigger(context, target, @minion_candle)]}
      _other -> {state, [trigger(context, target, @candle_fizzle)]}
    end
  end

  def apply(state, _context, _spell, _now), do: {state, []}

  defp costume(name, state) do
    case Map.fetch!(@costumes, name) do
      {male, female} -> if state.unit.gender == 1, do: female, else: male
      spell_id -> spell_id
    end
  end

  defp at_heart?(
         %{movement_block: %{position: {x, y, z, _o}}} = state,
         %CastContext{caster_position: {_world, cx, cy, cz}} = context
       ) do
    reach = @wondervolt_reach + (context.caster_bounding_radius || 0.0) + (state.unit.bounding_radius || 0.0)
    :math.sqrt((x - cx) ** 2 + (y - cy) ** 2 + (z - cz) ** 2) < reach
  end

  defp at_heart?(_state, _context), do: false

  defp pick(effects), do: %RandomChoice{choices: Enum.map(effects, &{1, [&1]})}

  defp trigger(%CastContext{caster_guid: caster, caster_level: level}, target_guid, spell_id),
    do: Effects.trigger_spell(caster, level, target_guid, spell_id)

  defp own_trigger(%{object: %{guid: guid}} = state, spell_id),
    do: Effects.trigger_spell(guid, state.unit.level || 1, guid, spell_id)
end
