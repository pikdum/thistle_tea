defmodule ThistleTea.Game.Core.OutdoorPvp.CapturePointLawsTest do
  use ExUnit.Case, async: true
  use Lynx.Case

  alias ThistleTea.Game.Core.OutdoorPvp.CapturePoint
  alias ThistleTea.Game.Core.OutdoorPvp.CapturePoint.Template

  def ticked_slider(max_time, min_time, neutral_percent, progress, alliance, horde, elapsed_ms) do
    template = %Template{
      entry: 0,
      radius: 0,
      display_state: 0,
      position_state: 0,
      neutral_state: 0,
      neutral_percent: neutral_percent,
      min_time: min_time,
      max_time: max_time
    }

    %CapturePoint{template: template, progress: progress}
    |> CapturePoint.advance(alliance, horde, elapsed_ms)
    |> CapturePoint.slider()
  end

  laws "CapturePoint slider" do
    cutoff &:elixir_erl_pass.no_parens_remote/2

    prelude ~LEAN"""
    module
    public import Lynx
    public import Lynx.Modules.Erlang.erlang

    @[expose] public section

    open Lynx

    namespace CapturePointWork

    theorem div_int (x y : Int) (hy : y ≠ 0) :
        Erlang.erlang.«div/2» (.integer x) (.integer y) = .ok (.integer (x.tdiv y)) := by
      simp [Erlang.erlang.«div/2», hy]

    theorem max_int (x y : Int) : Erlang.erlang.«max/2» (.integer x) (.integer y) = .ok (.integer (max x y)) := by
      simp only [Erlang.erlang.«max/2», Term.compare_integers]
      by_cases h : y ≤ x
      · simp [Int.isGE_compare, h, Int.max_eq_left h]
      · have le : x ≤ y := by omega
        simp [Int.isGE_compare, h, Int.max_eq_right le]

    theorem min_int (x y : Int) : Erlang.erlang.«min/2» (.integer x) (.integer y) = .ok (.integer (min x y)) := by
      simp only [Erlang.erlang.«min/2», Term.compare_integers]
      by_cases h : x ≤ y
      · simp [Int.isLE_compare, h, Int.min_eq_left h]
      · have le : y ≤ x := by omega
        simp [Int.isLE_compare, h, Int.min_eq_right le]

    theorem neg_int (x : Int) : Erlang.erlang.«-/1» (.integer x) = .ok (.integer (-x)) := rfl

    theorem gt_int (a b : Int) :
        Erlang.erlang.«>/2» (.integer a) (.integer b) = .ok (if b < a then Term.true else Term.false) := by
      simp [Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt]

    theorem eq_int (a b : Int) :
        Erlang.erlang.«==/2» (.integer a) (.integer b) = .ok (if a = b then Term.true else Term.false) := by
      simp [Erlang.erlang.«==/2»]

    set_option hygiene false in
    macro "refute_requires" : tactic => `(tactic| (simp [Erlang.erlang.«is_integer/1», CapturePointWork.gt_int, *] at requires; done))

    end CapturePointWork
    """

    law slider_in_range(max_time, min_time, neutral_percent, progress, alliance, horde, elapsed_ms),
      requires:
        is_integer(max_time) and max_time > 0 and is_integer(min_time) and min_time > 0 and
          is_integer(neutral_percent) and is_integer(progress) and is_integer(alliance) and alliance >= 0 and
          is_integer(horde) and horde >= 0 and is_integer(elapsed_ms) and elapsed_ms > 0,
      expects: ticked_slider(max_time, min_time, neutral_percent, progress, alliance, horde, elapsed_ms) in 0..100,
      proof: ~LEAN"""
      open Lynx CapturePointWork in
        simp only [«slider_in_range:requires/7»] at requires
        cases max_time <;> try refute_requires
        rename_i T
        by_cases hT : 0 < T
        case neg => refute_requires
        cases min_time <;> try refute_requires
        rename_i N
        by_cases hN : 0 < N
        case neg => refute_requires
        cases neutral_percent <;> try refute_requires
        rename_i P
        cases progress <;> try refute_requires
        rename_i G
        cases alliance <;> try refute_requires
        rename_i A
        by_cases hA : 0 ≤ A
        case neg => refute_requires
        cases horde <;> try refute_requires
        rename_i H
        by_cases hH : 0 ≤ H
        case neg => refute_requires
        cases elapsed_ms <;> try refute_requires
        rename_i E
        by_cases hE : 0 < E
        case neg => refute_requires
        clear requires
        have hT0 : T ≠ 0 := by omega
        have hN0 : N ≠ 0 := by omega
        simp only [«slider_in_range:ensures/7», «ticked_slider/7»]
        unfold CapturePoint.«advance/4»
        simp [Term.getMapKeys, gt_int, div_int, max_int, min_int, neg_int, hT0, hN0, hA, hH, hE,
          Erlang.erlang.«is_integer/1», Erlang.erlang.«is_map/1», Erlang.maps.«update/3»]
        have phase_ok : ∀ p m n d : Int, ∃ t, CapturePoint.«phase/4» (.integer p) (.integer m) (.integer n) (.integer d) = .ok t := by
          intro p m n d
          unfold CapturePoint.«phase/4»
          simp only [eq_int, gt_int, Erlang.erlang.«-/1», Erlang.erlang.«</2_integers», Erlang.erlang.«>=/2_integers»,
            Erlang.erlang.«=</2_integers», Lynx.Except.ok_bind]
          repeat' (first | exact ⟨_, rfl⟩ | split | simp only [Lynx.Except.tryWith_ok] | (exfalso; simp_all))
        generalize (T * 1000 * E).tdiv N = c
        generalize (A - H) * E = s
        have hp : -(T * 1000) ≤ min (max (G + min (max s (-c)) c) (-(T * 1000))) (T * 1000) ∧
            min (max (G + min (max s (-c)) c) (-(T * 1000))) (T * 1000) ≤ T * 1000 := by omega
        generalize min (max (G + min (max s (-c)) c) (-(T * 1000))) (T * 1000) = p at hp ⊢
        obtain ⟨t, ht⟩ := phase_ok p (T * 1000) ((T * 1000 * P).tdiv 100) (A - H)
        simp only [ht, Lynx.Except.ok_bind]
        unfold CapturePoint.«slider/1»
        simp [Term.getMapKeys, div_int, hT0]
        have nonneg : 0 ≤ (p + T * 1000) * 100 + T * 2000 - 1 := by omega
        have lo : 0 ≤ ((p + T * 1000) * 100 + T * 2000 - 1) / (T * 2000) := Int.ediv_nonneg nonneg (by omega)
        have hi : ((p + T * 1000) * 100 + T * 2000 - 1) / (T * 2000) ≤ 100 :=
          (Int.ediv_le_iff_le_mul (by omega)).mpr (by omega)
        simp [Int.tdiv_eq_ediv_of_nonneg nonneg, lo, hi]
      """
  end
end
