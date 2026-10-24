defmodule ThistleTea.Game.Core.GuidLawsTest do
  use ExUnit.Case, async: true
  use Lynx.Case

  alias ThistleTea.Game.Core.Guid

  laws "Guid.pack/1", options: [maxHeartbeats: 1_000_000] do
    prelude ~LEAN"""
    module
    public import Lynx

    @[expose] public section

    namespace GuidPacking

    open Lynx.Term.Bitstring

    theorem integerBits_mod (n width : Nat) :
        integerBits ((n % 2 ^ width : Nat) : Int) width false = integerBits n width false := by
      simpa only [decodeInteger_integerBits, integerBits_length] using
        integerBits_decodeInteger (integerBits n width false)

    def byte (g i : Nat) : Nat := (g >>> (8 * i)) % 256

    def mbit (b : Nat) : Nat := if b = 0 then 0 else 1

    def pk (b : Nat) : List Bool := if b = 0 then [] else integerBits b 8 false

    def maskBits (g : Nat) : List Bool :=
      integerBits (mbit (byte g 7) : Int) 1 false ++ integerBits (mbit (byte g 6) : Int) 1 false ++
      integerBits (mbit (byte g 5) : Int) 1 false ++ integerBits (mbit (byte g 4) : Int) 1 false ++
      integerBits (mbit (byte g 3) : Int) 1 false ++ integerBits (mbit (byte g 2) : Int) 1 false ++
      integerBits (mbit (byte g 1) : Int) 1 false ++ integerBits (mbit (byte g 0) : Int) 1 false

    def dataBits (g : Nat) : List Bool :=
      pk (byte g 0) ++ pk (byte g 1) ++ pk (byte g 2) ++ pk (byte g 3) ++
      pk (byte g 4) ++ pk (byte g 5) ++ pk (byte g 6) ++ pk (byte g 7)

    theorem byte_lt (g i : Nat) : byte g i < 256 := Nat.mod_lt _ (by decide)

    theorem mbit_lt (b : Nat) : mbit b < 2 := by unfold mbit; split <;> decide

    theorem pk_aligned (b : Nat) : (pk b).length % 8 = 0 := by unfold pk; split <;> simp

    theorem split_byte (g k : Nat) :
        integerBits (g : Int) (8 * (k + 1)) false =
          integerBits (byte g k : Int) 8 false ++ integerBits g (8 * k) false := by
      rw [show 8 * (k + 1) = 8 + 8 * k by omega, integerBits_add]
      congr 1
      rw [byte, show (256 : Nat) = 2 ^ 8 by rfl, integerBits_mod, Int.natCast_shiftRight]

    theorem bits64 (g : Nat) :
        integerBits (g : Int) 64 false =
          integerBits (byte g 7 : Int) 8 false ++ integerBits (byte g 6 : Int) 8 false ++
          integerBits (byte g 5 : Int) 8 false ++ integerBits (byte g 4 : Int) 8 false ++
          integerBits (byte g 3 : Int) 8 false ++ integerBits (byte g 2 : Int) 8 false ++
          integerBits (byte g 1 : Int) 8 false ++ integerBits (byte g 0 : Int) 8 false := by
      have h := fun k => split_byte g k
      rw [show 64 = 8 * (7 + 1) by rfl, h 7, show 8 * 7 = 8 * (6 + 1) by rfl, h 6,
        show 8 * 6 = 8 * (5 + 1) by rfl, h 5, show 8 * 5 = 8 * (4 + 1) by rfl, h 4,
        show 8 * 4 = 8 * (3 + 1) by rfl, h 3, show 8 * 3 = 8 * (2 + 1) by rfl, h 2,
        show 8 * 2 = 8 * (1 + 1) by rfl, h 1, show 8 * 1 = 8 * (0 + 1) by rfl, h 0]
      simp [integerBits]

    theorem match_bit (b : Nat) (hb : b < 2) (tail : List Bool) :
        matchInteger (ofBits (integerBits b 1 false ++ tail)) (.integer 1) 1 false false =
          some (.integer b, ofBits tail) := by
      simpa [decodeInteger_integerBits, Nat.mod_eq_of_lt hb] using
        matchInteger_prefix (integerBits b 1 false) tail

    theorem match_byte (b : Nat) (hb : b < 256) (tail : List Bool) :
        matchInteger (ofBits (integerBits b 8 false ++ tail)) (.integer 8) 1 false false =
          some (.integer b, ofBits tail) := by
      simpa [decodeInteger_integerBits, Nat.mod_eq_of_lt hb] using
        matchInteger_prefix (integerBits b 8 false) tail

    theorem match_byte_end (b : Nat) (hb : b < 256) :
        matchInteger (ofBits (integerBits b 8 false)) (.integer 8) 1 false false =
          some (.integer b, ofBits []) := by
      simpa using match_byte b hb []

    theorem match64 (g : Nat) (hg : g < 2 ^ 64) :
        matchInteger (ofBits (integerBits (byte g 7 : Int) 8 false ++
          (integerBits (byte g 6 : Int) 8 false ++ (integerBits (byte g 5 : Int) 8 false ++
          (integerBits (byte g 4 : Int) 8 false ++ (integerBits (byte g 3 : Int) 8 false ++
          (integerBits (byte g 2 : Int) 8 false ++ (integerBits (byte g 1 : Int) 8 false ++
          integerBits (byte g 0 : Int) 8 false))))))))
          (.integer 64) 1 false false = some (.integer g, ofBits []) := by
      have whole := bits64 g
      simp only [List.append_assoc] at whole
      rw [← whole]
      refine (matchInteger_take (integerBits (g : Int) 64 false) 64 (by simp)).trans ?_
      have len := integerBits_length (g : Int) 64 false
      simp only [List.take_of_length_le (Nat.le_of_eq len), List.drop_of_length_le (Nat.le_of_eq len),
        decodeInteger_integerBits, Nat.mod_eq_of_lt hg]

    theorem seg1 (v : Int) :
        integerSegment (.integer v) (.integer 1) 1 false = .ok (ofBits (integerBits v 1 false)) :=
      integerSegment_bits v 1

    theorem seg8 (v : Int) :
        integerSegment (.integer v) (.integer 8) 1 false = .ok (ofBits (integerBits v 8 false)) :=
      integerSegment_bits v 8

    theorem seg64 (v : Int) :
        integerSegment (.integer v) (.integer 64) 1 false = .ok (ofBits (integerBits v 64 false)) :=
      integerSegment_bits v 64

    theorem bin8 (bits : List Bool) (aligned : bits.length % 8 = 0) :
        binarySegment (ofBits bits) (.atom "all") 8 = .ok (ofBits bits) := by
      simp only [binarySegment, ofBits, pack_bitSize]
      simp [aligned]

    theorem tail8 (bits : List Bool) (aligned : bits.length % 8 = 0) :
        matchTail (ofBits bits) (.atom "all") 8 = true := by
      simp only [matchTail, ofBits, pack_bitSize]
      simp [aligned]

    theorem len_mod_append (a b : List Bool) (ha : a.length % 8 = 0) :
        (a ++ b).length % 8 = b.length % 8 := by
      simp only [List.length_append]; omega

    theorem packed_aligned (g : Nat) : (maskBits g ++ dataBits g).length % 8 = 0 := by
      simp only [maskBits, dataBits, List.length_append, integerBits_length]
      have := pk_aligned (byte g 0); have := pk_aligned (byte g 1); have := pk_aligned (byte g 2)
      have := pk_aligned (byte g 3); have := pk_aligned (byte g 4); have := pk_aligned (byte g 5)
      have := pk_aligned (byte g 6); have := pk_aligned (byte g 7)
      omega

    end GuidPacking
    """

    law pack_roundtrip(guid, suffix),
      requires: is_integer(guid) and guid >= 0 and guid <= 0xFFFFFFFFFFFFFFFF and is_binary(suffix),
      expects: Guid.unpack(Guid.pack(guid) <> suffix) === {guid, suffix},
      proof: ~LEAN"""
      open Lynx.Term.Bitstring GuidPacking in
        have present_eq (b : Nat) :
            Guid.«present/1» (.integer b) = .ok (.integer (mbit b)) := by
          unfold Guid.«present/1» mbit
          by_cases h : b = 0
          · subst h; rfl
          · simp [h]
        have packed_eq (b : Nat) : Guid.«packed/1» (.integer b) = .ok (ofBits (pk b)) := by
          unfold Guid.«packed/1» pk
          by_cases h : b = 0
          · subst h; rfl
          · simp [h, seg8]
        have take_byte_eq (b : Nat) (hb : b < 256) (tail : List Bool) (aligned : tail.length % 8 = 0) :
            Guid.«take_byte/2» (.integer (mbit b)) (ofBits (pk b ++ tail)) =
              .ok (.tuple #[.integer b, ofBits tail]) := by
          unfold Guid.«take_byte/2» mbit pk
          by_cases h : b = 0
          · subst h; rfl
          · simp [h, match_byte b hb, tail8 tail aligned]
        have pack_eq (g : Nat) :
            Guid.«pack/1» (.integer g) = .ok (ofBits (maskBits g ++ dataBits g)) := by
          unfold Guid.«pack/1»
          simp only [Guid.«pack_bytes/1», seg64, bits64, List.append_assoc, Except.bind, Lynx.Except.ok_bind,
            match_byte _ (byte_lt _ _), match_byte_end _ (byte_lt _ _), extract_some, matchEnd_bits,
            List.length_nil, beq_self_eq_true, present_eq, packed_eq, seg1, bin8 _ (pk_aligned _),
            append_bits, maskBits, dataBits]
        have unpack_eq (g : Nat) (hg : g < 2 ^ 64) (S : List Bool) (hS : S.length % 8 = 0) :
            Guid.«unpack/1» (ofBits (maskBits g ++ dataBits g ++ S)) =
              .ok (.tuple #[.integer g, ofBits S]) := by
          unfold Guid.«unpack/1»
          simp only [maskBits, dataBits, List.append_assoc, Except.bind, Lynx.Except.ok_bind,
            match_bit _ (mbit_lt _), extract_some, tail8, len_mod_append, pk_aligned, hS,
            take_byte_eq _ (byte_lt _ _), seg8, append_bits, match64 g hg, matchEnd_bits]
          rfl
        cases guid <;> simp [«pack_roundtrip:requires/2», Erlang.erlang.«is_integer/1»] at requires
        rename_i z
        have h0 : 0 ≤ z := by
          by_cases h : 0 ≤ z
          · exact h
          · simp [h] at requires
        have h1 : z ≤ 18446744073709551615 := by
          by_cases h : z ≤ 18446744073709551615
          · exact h
          · simp [h0, h] at requires
        simp only [h0, h1, if_true] at requires
        cases suffix <;> simp [Erlang.erlang.«is_binary/1»] at requires
        rename_i bytes last valid
        split at requires
        · rename_i same
          cases same
          obtain ⟨g, rfl⟩ := Int.eq_ofNat_of_zero_le h0
          have hg : g < 2 ^ 64 := by omega
          have hs : Lynx.Term.bitstring bytes 0 valid = ofBits (toBits bytes 0) :=
            (ofBits_toBits_aligned bytes).symm
          have hS : (toBits bytes 0).length % 8 = 0 := by rw [toBits_length_aligned]; omega
          rw [hs]
          simp only [«pack_roundtrip:ensures/2», Lynx.Except.ok_bind, pack_eq, Except.bind,
            bin8 _ (packed_aligned g), bin8 _ hS, append_bits, unpack_eq g hg _ hS]
          simp [Erlang.erlang.«=:=/2»]
        · simp at requires
      """
  end
end
