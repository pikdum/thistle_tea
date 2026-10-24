defmodule ThistleTea.Game.Network.Connection.CryptoLawsTest do
  use ExUnit.Case, async: true
  use Lynx.Case

  alias ThistleTea.Game.Network.Connection
  alias ThistleTea.Game.Network.Connection.Crypto

  def framed?(<<size::16, _opcode::32>>, body), do: byte_size(body) + 4 >= size
  def framed?(_header, _body), do: false

  def roundtrips?(key, header, i, j, body) do
    {:ok, sender, encrypted} = Crypto.encrypt_header(%Connection{session_key: key, send_i: i, send_j: j}, header)
    receiver = %Connection{session_key: key, recv_i: i, recv_j: j, binary_stream: encrypted <> body}
    {:ok, receiver, decrypted} = Crypto.decrypt_header(receiver)
    decrypted == header and receiver.recv_i == sender.send_i and receiver.recv_j == sender.send_j
  end

  laws "Crypto header cipher" do
    cutoff &:elixir_erl_pass.no_parens_remote/2

    prelude ~LEAN"""
    module
    public import Lynx
    public import Lynx.Modules.Erlang.erlang
    import all Lynx.Term.Compare

    @[expose] public section

    open Lynx Lynx.Term.Bitstring

    namespace CipherWork

    abbrev bs (l : List UInt8) : Lynx.Term := .bitstring ⟨l.toArray⟩ 0 (valid_aligned _)

    def lowByte (x : Int) : UInt8 := UInt8.ofNat (x % 256).toNat

    def ixor : Int → Int → Int
      | .ofNat x, .ofNat y => .ofNat (x ^^^ y)
      | .ofNat x, .negSucc y => .negSucc (x ^^^ y)
      | .negSucc x, .ofNat y => .negSucc (x ^^^ y)
      | .negSucc x, .negSucc y => .ofNat (x ^^^ y)

    theorem bxor_eq (a b : Int) : Erlang.erlang.«bxor/2» (.integer a) (.integer b) = .ok (.integer (ixor a b)) := by
      cases a <;> cases b <;> rfl

    theorem matchEnd_nil : matchEnd (bs []) = true := rfl

    theorem matchEnd_cons (b : UInt8) (l : List UInt8) : matchEnd (bs (b :: l)) = false := by
      have size : (⟨(b :: l).toArray⟩ : ByteArray).size = l.length + 1 := by simp [ByteArray.size]
      simp only [matchEnd, bitSize, size]
      simp

    theorem matchByte (b : UInt8) (l : List UInt8) :
        matchInteger (bs (b :: l)) (.integer 8) 1 false false = some (.integer b.toNat, bs l) :=
      matchInteger_byte b l _

    theorem matchTail_bs (l : List UInt8) : matchTail (bs l) (.atom "all") 8 = true := by
      simp [matchTail, bitSize]
      split <;> omega

    theorem binarySegment_bs (l : List UInt8) : binarySegment (bs l) (.atom "all") 8 = .ok (bs l) :=
      binarySegment_aligned _

    theorem append_bs (l r : List UInt8) : append (bs l) (bs r) = .ok (bs (l ++ r)) := append_bytes l r

    theorem bit_low (x : Int) (s : Nat) (hs : s < 8) : (x >>> s) % 2 = ((x % 256) >>> s) % 2 := by
      rw [Int.shiftRight_eq_div_pow, Int.shiftRight_eq_div_pow]
      rcases s with _ | _ | _ | _ | _ | _ | _ | _ | s
      all_goals first | (simp; omega) | omega

    theorem integerBits_little8 (x : Int) :
        integerBits x 8 true = integerBits (lowByte x).toNat 8 false := by
      have low : ((lowByte x).toNat : Int) = x % 256 := by
        simp only [lowByte, UInt8.toNat_ofNat']
        have h0 : 0 ≤ x % 256 := Int.emod_nonneg _ (by decide)
        have h1 : x % 256 < 256 := Int.emod_lt_of_pos _ (by decide)
        rw [Nat.mod_eq_of_lt (by omega), Int.toNat_of_nonneg h0]
      rw [low]
      simp only [integerBits]
      apply List.map_congr_left
      intro i hi
      have hi : i < 8 := List.mem_range.mp hi
      simp only [↓reduceIte, Bool.false_eq_true]
      have shift : i / 8 * 8 + (min 8 (8 - i / 8 * 8) - 1 - i % 8) = 8 - 1 - i := by omega
      rw [shift, bit_low x _ (by omega)]

    theorem seg8_little (x : Int) :
        integerSegment (.integer x) (.integer 8) 1 true = .ok (bs [lowByte x]) := by
      have h1 : integerSegment (.integer x) (.integer 8) 1 true = .ok (ofBits (integerBits x 8 true)) := by
        simp [integerSegment]
      rw [h1, integerBits_little8]
      exact (integerSegment_bits _ 8).symm.trans (integerSegment_byte (lowByte x))

    theorem seg8_byte (b : UInt8) :
        integerSegment (.integer b.toNat) (.integer 8) 1 false = .ok (bs [b]) := integerSegment_byte b

    theorem matchBinary_ofBits (bits : List Bool) (n : Nat) (hn : n * 8 ≤ bits.length) :
        matchBinary (ofBits bits) (.integer n) 8 = some (ofBits (bits.take (n * 8)), ofBits (bits.drop (n * 8))) := by
      simp [matchBinary, ofBits, pack_toBits, hn]

    theorem matchBinary_bs (h r : List UInt8) :
        matchBinary (bs (h ++ r)) (.integer h.length) 8 = some (bs h, bs r) := by
      have joined : bs (h ++ r) = ofBits (toBits ⟨h.toArray⟩ 0 ++ toBits ⟨r.toArray⟩ 0) := by
        have := append_bs h r
        simp only [append] at this
        exact (Except.ok.inj this).symm
      have len : (toBits ⟨h.toArray⟩ 0).length = h.length * 8 := by
        rw [toBits_length_aligned]; simp [ByteArray.size]
      rw [joined, matchBinary_ofBits _ _ (by simp [len]), ← len, List.take_left, List.drop_left,
        ofBits_toBits_aligned, ofBits_toBits_aligned]

    theorem key_lookup (K : List UInt8) (idx : Nat) (h : idx < K.length) :
        matchBinary (bs K) (.integer idx) 8 = some (bs (K.take idx), bs (K.getD idx 0 :: K.drop (idx + 1))) := by
      have e := matchBinary_bs (K.take idx) (K.drop idx)
      rw [List.take_append_drop, List.length_take, Nat.min_eq_left (Nat.le_of_lt h)] at e
      rw [e, List.drop_eq_getElem_cons h]
      simp [List.getD, List.getElem?_eq_getElem h]

    theorem rem_nat (i n : Nat) (hn : n ≠ 0) :
        Erlang.erlang.«rem/2» (.integer i) (.integer n) = .ok (.integer (i % n : Nat)) := by
      simp only [Erlang.erlang.«rem/2»]
      rw [if_neg (by omega)]
      rfl

    theorem ixor_nat (a b : Nat) : ixor a b = ((a ^^^ b : Nat) : Int) := rfl

    theorem lowByte_nat (b : Nat) (hb : b < 256) : lowByte b = UInt8.ofNat b := by
      simp only [lowByte]
      congr 1
      omega

    theorem complement_byte : ∀ a : Fin 256, 255 - a.val = 255 ^^^ a.val := by decide +kernel

    theorem negative_byte (y k : Nat) (hy : y < 256) (hk : k < 256) :
        lowByte (ixor ((y : Int) - 256) k) = UInt8.ofNat (y ^^^ k) := by
      have neg : ((y : Int) - 256) = Int.negSucc (255 - y) := by
        rw [Int.negSucc_eq]; omega
      have bound : (255 - y) ^^^ k < 256 := Nat.xor_lt_two_pow (n := 8) (by omega) (by omega)
      have comp := complement_byte ⟨y, hy⟩
      have comp2 := complement_byte ⟨(255 - y) ^^^ k, bound⟩
      simp only at comp comp2
      rw [neg]
      simp only [ixor, lowByte]
      apply congrArg UInt8.ofNat
      have low : (Int.negSucc ((255 - y) ^^^ k) % 256).toNat = 255 - ((255 - y) ^^^ k) := by
        rw [Int.negSucc_eq]; omega
      rw [low, comp2, comp, ← Nat.xor_assoc, ← Nat.xor_assoc, Nat.xor_self, Nat.zero_xor]

    def kb (K : List UInt8) (i : Nat) : Nat := (K.getD (i % K.length) 0).toNat

    def encL (K : List UInt8) : List UInt8 → Nat → Int → List UInt8 × Nat × Int
      | [], i, j => ([], i, j)
      | b :: l, i, j =>
        let x := lowByte (((b.toNat ^^^ kb K i : Nat) : Int) + j)
        let r := encL K l (i % K.length + 1) x.toNat
        (x :: r.1, r.2.1, r.2.2)

    def decL (K : List UInt8) : List UInt8 → Nat → Int → List UInt8 × Nat × Int
      | [], i, j => ([], i, j)
      | c :: l, i, j =>
        let x := lowByte (ixor (c.toNat - j) (kb K i))
        let r := decL K l (i % K.length + 1) c.toNat
        (x :: r.1, r.2.1, r.2.2)

    theorem lowByte_toNat (x : Int) : ((lowByte x).toNat : Int) = x % 256 := by
      simp only [lowByte, UInt8.toNat_ofNat']
      have h0 : 0 ≤ x % 256 := Int.emod_nonneg _ (by decide)
      have h1 : x % 256 < 256 := Int.emod_lt_of_pos _ (by decide)
      rw [Nat.mod_eq_of_lt (by omega), Int.toNat_of_nonneg h0]

    theorem byte_roundtrip (b k : Nat) (hb : b < 256) (hk : k < 256) (j : Int) (hj0 : 0 ≤ j) (hj1 : j < 256) :
        lowByte ((((lowByte (((b ^^^ k : Nat) : Int) + j)).toNat : Int) - j) |> (ixor · k)) = UInt8.ofNat b := by
      have hy : b ^^^ k < 256 := Nat.xor_lt_two_pow (n := 8) hb hk
      have back : (b ^^^ k) ^^^ k = b := by rw [Nat.xor_assoc, Nat.xor_self, Nat.xor_zero]
      simp only
      rw [lowByte_toNat]
      by_cases small : ((b ^^^ k : Nat) : Int) + j < 256
      · have : (((b ^^^ k : Nat) : Int) + j) % 256 - j = ((b ^^^ k : Nat) : Int) := by omega
        rw [this, ixor_nat, back, lowByte_nat b hb]
      · have : (((b ^^^ k : Nat) : Int) + j) % 256 - j = ((b ^^^ k : Nat) : Int) - 256 := by omega
        rw [this, negative_byte _ _ hy hk, back]

    theorem model_roundtrip (K : List UInt8) : ∀ (l : List UInt8) (i : Nat) (j : Int), 0 ≤ j → j < 256 →
        decL K (encL K l i j).1 i j = (l, (encL K l i j).2.1, (encL K l i j).2.2)
      | [], _, _, _, _ => rfl
      | b :: l, i, j, hj0, hj1 => by
        have step := byte_roundtrip b.toNat (kb K i) (UInt8.toNat_lt b) (UInt8.toNat_lt _) j hj0 hj1
        simp only at step
        have x8 := UInt8.toNat_lt (lowByte (((b.toNat ^^^ kb K i : Nat) : Int) + j))
        have ih := model_roundtrip K l (i % K.length + 1)
          ((lowByte (((b.toNat ^^^ kb K i : Nat) : Int) + j)).toNat) (by omega) (by omega)
        simp only [encL, decL, step, UInt8.ofNat_toNat, ih]

    theorem enc_length (K : List UInt8) : ∀ (l : List UInt8) (i : Nat) (j : Int), (encL K l i j).1.length = l.length
      | [], _, _ => rfl
      | _ :: l, i, _ => by simp [encL, enc_length K l]

    theorem is_binary_bitstring (b : ByteArray) (l : Fin 8) (v : Valid b l) :
        Erlang.erlang.«is_binary/1» (.bitstring b l v) = .ok (if l = 0 then Term.true else Term.false) := by
      by_cases h : l = 0
      · subst h; rfl
      · simp only [Erlang.erlang.«is_binary/1», h, if_false]
        split
        · rename_i heq; cases heq; contradiction
        · rfl

    theorem aligned_bs (b : ByteArray) (v : Valid b 0) : Term.bitstring b 0 v = bs b.data.toList := by
      rcases b with ⟨⟨l⟩⟩; rfl

    theorem bs_compare_atom (l : List UInt8) (a : String) : Term.compare (bs l) (.atom a) = .gt := by
      rw [Term.compare_eq_step]; rfl

    theorem empty_bs (p) : Term.bitstring ⟨#[]⟩ 0 p = bs [] := rfl

    theorem eq_nil (l : List UInt8) : Erlang.erlang.«==/2» (bs l) (.atom "nil") = .ok Term.false := by
      simp [Erlang.erlang.«==/2», bs_compare_atom]

    theorem matchBinary_fixed (h r : List UInt8) (n : Int) (hn : (h.length : Int) = n) :
        matchBinary (bs (h ++ r)) (.integer n) 8 = some (bs h, bs r) := by
      subst hn; exact matchBinary_bs h r

    theorem is_binary_bs (l : List UInt8) : Erlang.erlang.«is_binary/1» (bs l) = .ok Term.true := rfl

    theorem gt_integers (a b : Int) :
        Erlang.erlang.«>/2» (.integer a) (.integer b) = .ok (if b < a then Term.true else Term.false) := by
      simp [Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt]

    theorem byte_size_bs (l : List UInt8) : Erlang.erlang.«byte_size/1» (bs l) = .ok (.integer l.length) := by
      simp [Erlang.erlang.«byte_size/1», ByteArray.size]

    theorem matchInteger_split (l r : List UInt8) (little : Bool) :
        ∃ v, matchInteger (bs (l ++ r)) (.integer (l.length * 8 : Nat)) 1 false little = some (v, bs r) := by
      have joined : bs (l ++ r) = ofBits (toBits ⟨l.toArray⟩ 0 ++ toBits ⟨r.toArray⟩ 0) := by
        have := append_bs l r
        simp only [append] at this
        exact (Except.ok.inj this).symm
      have len : (toBits ⟨l.toArray⟩ 0).length = l.length * 8 := by
        rw [toBits_length_aligned]; simp [ByteArray.size]
      have hr : ofBits (toBits ⟨r.toArray⟩ 0) = bs r := ofBits_toBits_aligned _
      rw [joined, ← hr, ← len]
      generalize toBits ⟨l.toArray⟩ 0 = L
      generalize toBits ⟨r.toArray⟩ 0 = R
      unfold matchInteger
      simp only [ofBits, pack_toBits]
      simp

    theorem match16 (a b : UInt8) (rest : List UInt8) :
        matchInteger (bs (a :: b :: rest)) (.integer 16) 1 false false =
          some (.integer ((a.toNat * 256 + b.toNat : Nat) : Int), bs rest) := by
      have := matchInteger_bytes [a, b] rest (valid_aligned _) 16 (by simp)
      simpa using this

    theorem match32 (a b c d : UInt8) (little : Bool) :
        ∃ v, matchInteger (bs [a, b, c, d]) (.integer 32) 1 false little = some (v, bs []) :=
      matchInteger_split [a, b, c, d] [] little

    set_option hygiene false in
    macro "refute_requires" : tactic => `(tactic| (simp [Erlang.erlang.«is_binary/1», Erlang.erlang.«is_integer/1», Erlang.erlang.«==/2», CipherWork.byte_size_bs, CipherWork.gt_integers, *] at requires; done))

    end CipherWork
    """

    law header_roundtrip(key, header, i, j, body),
      requires:
        is_binary(key) and byte_size(key) > 0 and is_binary(header) and byte_size(header) == 6 and
          is_integer(i) and i >= 0 and is_integer(j) and j >= 0 and j < 256 and is_binary(body) and
          framed?(header, body),
      expects: roundtrips?(key, header, i, j, body),
      proof: ~LEAN"""
      open Lynx Lynx.Term.Bitstring CipherWork in
        simp only [«header_roundtrip:requires/5»] at requires
        cases key <;> try refute_requires
        rename_i keyBytes kl kv
        by_cases hkl : kl = 0
        case neg => rw [is_binary_bitstring] at requires; refute_requires
        subst hkl; rw [aligned_bs] at requires ⊢; generalize keyBytes.data.toList = K at requires ⊢
        by_cases hK : 0 < K.length
        case neg => refute_requires
        cases header <;> try refute_requires
        rename_i hb hl hv
        by_cases hhl : hl = 0
        case neg => rw [is_binary_bitstring] at requires; refute_requires
        subst hhl; rw [aligned_bs] at requires ⊢; generalize hb.data.toList = H at requires ⊢
        by_cases hH : (H.length : Int) = 6
        case neg => refute_requires
        cases i <;> try refute_requires
        rename_i i
        by_cases hi : 0 ≤ i
        case neg => refute_requires
        cases j <;> try refute_requires
        rename_i j
        by_cases hj0 : 0 ≤ j
        case neg => refute_requires
        by_cases hj1 : j < 256
        case neg => refute_requires
        cases body <;> try refute_requires
        rename_i bb bl bv
        by_cases hbl : bl = 0
        case neg => rw [is_binary_bitstring] at requires; refute_requires
        subst hbl; rw [aligned_bs] at requires ⊢; generalize bb.data.toList = B at requires ⊢
        simp [Erlang.erlang.«is_binary/1», Erlang.erlang.«is_integer/1», Erlang.erlang.«==/2», byte_size_bs, gt_integers, *] at requires
        have h6 : H.length = 6 := by omega
        obtain ⟨h0, h1, h2, h3, h4, h5, rfl⟩ : ∃ a b c d e f, H = [a, b, c, d, e, f] := by
          rcases H with _ | ⟨a, _ | ⟨b, _ | ⟨c, _ | ⟨d, _ | ⟨e, _ | ⟨f, _ | ⟨g, t⟩⟩⟩⟩⟩⟩⟩ <;> simp at h6
          exact ⟨a, b, c, d, e, f, rfl⟩
        obtain ⟨op, hop⟩ := match32 h2 h3 h4 h5 false
        simp only [«framed?/2», match16, extract_some, hop, matchEnd_nil, byte_size_bs, Lynx.Except.ok_bind,
          Erlang.erlang.«+/2_integers», Erlang.erlang.«>=/2_integers»] at requires
        have size : ((h0.toNat * 256 + h1.toNat : Nat) : Int) ≤ B.length + 4 := by
          by_cases c : ((h0.toNat * 256 + h1.toNat : Nat) : Int) ≤ B.length + 4
          · exact c
          · simp at requires; omega
        have hk0 : K.length ≠ 0 := by omega
        have enc_eq : ∀ (l acc : List UInt8) (i : Nat) (j : Int),
            Crypto.«encrypt_bytes/6» (bs l) (bs K) (.integer K.length) (.integer i) (.integer j) (bs acc) =
              .ok (.tuple #[bs (acc ++ (encL K l i j).1), .integer (encL K l i j).2.1, .integer (encL K l i j).2.2]) := by
          intro l
          induction l with
          | nil =>
            intro acc i j
            rw [Crypto.«encrypt_bytes/6».eq_def]
            simp [matchEnd_nil, encL]
          | cons b l ih =>
            intro acc i j
            rw [Crypto.«encrypt_bytes/6».eq_def]
            have ih := ih (acc ++ [lowByte (((b.toNat ^^^ kb K i : Nat) : Int) + j)]) (i % K.length + 1)
              (lowByte (((b.toNat ^^^ kb K i : Nat) : Int) + j)).toNat
            simp only [kb] at ih
            rw [show ((i % K.length + 1 : Nat) : Int) = ((i % K.length : Nat) : Int) + 1 by omega] at ih
            simp only [matchEnd_cons, matchByte, extract_some, matchTail_bs, rem_nat i K.length hk0,
              Lynx.Except.ok_bind, key_lookup K _ (Nat.mod_lt _ (Nat.pos_of_ne_zero hk0)), bxor_eq, ixor_nat,
              Erlang.erlang.«+/2_integers», seg8_little, matchEnd_nil, binarySegment_bs, seg8_byte, append_bs,
              Except.bind]
            rw [ih]
            simp [encL, kb]
        have dec_eq : ∀ (l acc : List UInt8) (i : Nat) (j : Int),
            Crypto.«decrypt_bytes/6» (bs l) (bs K) (.integer K.length) (.integer i) (.integer j) (bs acc) =
              .ok (.tuple #[bs (acc ++ (decL K l i j).1), .integer (decL K l i j).2.1, .integer (decL K l i j).2.2]) := by
          intro l
          induction l with
          | nil =>
            intro acc i j
            rw [Crypto.«decrypt_bytes/6».eq_def]
            simp [matchEnd_nil, decL]
          | cons c l ih =>
            intro acc i j
            rw [Crypto.«decrypt_bytes/6».eq_def]
            have ih := ih (acc ++ [lowByte (ixor (c.toNat - j) (kb K i))]) (i % K.length + 1) c.toNat
            simp only [kb] at ih
            rw [show ((i % K.length + 1 : Nat) : Int) = ((i % K.length : Nat) : Int) + 1 by omega] at ih
            simp only [matchEnd_cons, matchByte, extract_some, matchTail_bs, rem_nat i K.length hk0,
              Lynx.Except.ok_bind, key_lookup K _ (Nat.mod_lt _ (Nat.pos_of_ne_zero hk0)), bxor_eq,
              Erlang.erlang.«-/2_integers», Erlang.erlang.«+/2_integers», seg8_little, matchEnd_nil,
              binarySegment_bs, seg8_byte, append_bs, Except.bind]
            rw [ih]
            simp [decL, kb]
        obtain ⟨i, rfl⟩ := Int.eq_ofNat_of_zero_le hi
        simp only [«header_roundtrip:ensures/5», «roundtrips?/5», Lynx.Except.ok_bind, Crypto.«encrypt_header/2»,
          Term.getMapKeys, byte_size_bs, enc_eq, Erlang.maps.«update/3»]
        simp [Term.getMapKeys]
        rw [byte_size_bs, Lynx.Except.ok_bind, empty_bs, enc_eq]
        simp only [Lynx.Except.ok_bind, List.nil_append, Erlang.erlang.«is_map/1», Lynx.Except.tryWith_ok]
        have rt := model_roundtrip K [h0, h1, h2, h3, h4, h5] i j hj0 hj1
        have hlen := enc_length K [h0, h1, h2, h3, h4, h5] i j
        generalize encL K [h0, h1, h2, h3, h4, h5] i j = E at rt hlen ⊢
        obtain ⟨E, si, sj⟩ := E
        simp only [List.nil_append] at rt hlen ⊢
        simp only [Lynx.Except.ok_bind, binarySegment_bs, append_bs, Except.bind]
        unfold Crypto.«decrypt_header/1»
        simp [Term.getMapKeys]
        rw [binarySegment_bs]
        simp only []
        rw [append_bs]
        simp only [Lynx.Except.ok_bind, eq_nil, Lynx.Except.tryWith_ok]
        rw [matchBinary_fixed E B 6 (by simp [hlen])]
        simp only [extract_some, matchTail_bs]
        rw [byte_size_bs, Lynx.Except.ok_bind, empty_bs, dec_eq, rt]
        obtain ⟨opc, hopc⟩ := match32 h2 h3 h4 h5 true
        simp only [List.nil_append]
        simp
        rw [byte_size_bs, Lynx.Except.ok_bind, match16]
        simp only [extract_some, hopc, matchEnd_nil]
        simp [Erlang.erlang.«is_map/1», Erlang.maps.«update/3», Term.getMapKeys]
        have nlt : ¬ ((B.length : Int) < h0.toNat * 256 + h1.toNat - 4) := by omega
        simp [nlt, Erlang.erlang.«==/2»]
      """
  end
end
