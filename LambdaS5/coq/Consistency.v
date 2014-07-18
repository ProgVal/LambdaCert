Add LoadPath "../../jscert/coq/".
Add LoadPath "../../jscert/tlc/".
Add Rec LoadPath "../../jscert/flocq/src/" as Flocq.
Require Import String.
Require Import Store.
Require Import Values.
Require Import Context.
Require Import HeapUtils.
Require Import Interpreter.
Require Import LibNat.
Require Import LibLogic.
Require Import LibTactics.
Module Heap := Values.Heap.


(******** Definitions ********)

Definition ok_loc st loc :=
  Heap.indom (Store.value_heap st) loc
.
Definition ignore_loc {X : Type} (st : Store.store) (something : X) :=
  Logic.True
.
Definition ok_loc_option st loc_option :=
  match loc_option with
  | Some loc => ok_loc st loc
  | None => Logic.True
  end
.

Definition all_locs_in_loc_heap_exist (st : Store.store) : Prop :=
  forall (i : Values.id) l,
  Heap.binds (Store.loc_heap st) i l ->
  ok_loc st l
.

(* TODO: Check props too *)
Definition object_locs_exist (st : Store.store) (obj : Values.object) :=
  forall proto_loc class extensible primval_opt_loc props code_opt_loc,
  obj = object_intro proto_loc class extensible primval_opt_loc props code_opt_loc ->
  ok_loc st proto_loc /\ ok_loc_option st primval_opt_loc /\ ok_loc_option st code_opt_loc
.
Definition all_locs_in_obj_heap_exist (st : Store.store) : Prop :=
  forall (ptr : Values.object_ptr) obj,
  Heap.binds (Store.object_heap st) ptr obj ->
  object_locs_exist st obj
.

Definition all_locs_exist (st : Store.store) : Prop :=
  (all_locs_in_loc_heap_exist st) /\ (all_locs_in_obj_heap_exist st)
.

Inductive result_value_loc_exists {value_type : Type} (ok : Store.store -> value_type -> Prop) (st : store) : (@Context.result value_type) -> Prop :=
  | result_value_loc_exists_return : forall (v : value_type),
      ok st v ->
      result_value_loc_exists ok st (Return v)
  | result_value_loc_exists_exception : forall (l : Values.value_loc),
      ok_loc st l ->
      result_value_loc_exists ok st (Exception l)
  | result_value_loc_exists_break : forall (b : string) (l : Values.value_loc),
      ok_loc st l ->
      result_value_loc_exists ok st (Break b l)
  | result_value_loc_exists_fail : forall (s : string),
      result_value_loc_exists ok st (Fail s)
.

Lemma result_value_loc_exists_change_ok_exception :
  forall X Y st v ok1 ok2,
  result_value_loc_exists ok1 st (@Exception X v) ->
  result_value_loc_exists ok2 st (@Exception Y v)
.
Proof.
  intros X Y st v ok1 ok2 H.
  apply result_value_loc_exists_exception.
  inversion H.
  assumption.
Qed.


Lemma result_value_loc_exists_change_ok_break :
  forall X Y st v ok1 ok2 b c,
  result_value_loc_exists ok1 st (@Break X b v) ->
  result_value_loc_exists ok2 st (@Break Y c v)
.
Proof.
  intros X Y st v ok1 ok2 b c H.
  apply result_value_loc_exists_break.
  inversion H.
  assumption.
Qed.


(* st2 is a superset of st. *)
Definition superstore (st st2 : Store.store) :=
  forall loc, ok_loc st loc -> ok_loc st2 loc
.

Definition runs_type_eval_preserves_all_locs_exist runs :=
  forall st e st2 res,
  runs_type_eval runs st e = (st2, res) ->
  superstore st st2 /\ all_locs_exist st2 /\
  result_value_loc_exists ok_loc st2 res
.

Lemma superstore_ok_loc_option :
  forall st st2 oloc,
  superstore st st2 ->
  ok_loc_option st oloc ->
  ok_loc_option st2 oloc
.
Proof.
  intros st st2 oloc H IH.
  unfold ok_loc_option.
  unfold ok_loc_option in IH.
  destruct oloc.
    apply H.
    apply IH.

    auto.
Qed.

Lemma fresh_loc_preserves_ok_loc :
  forall obj_heap val_heap loc_heap fresh_locs loc n,
  ok_loc (store_intro obj_heap val_heap loc_heap (LibStream.stream_intro n fresh_locs)) loc ->
  ok_loc (store_intro obj_heap val_heap loc_heap fresh_locs) loc
.
Proof.
  intros obj_heap val_heap loc_heap fresh_locs loc n IH.
  unfold ok_loc.
  unfold ok_loc in IH.
  simpl.
  simpl in IH.
  apply IH.
Qed.

Lemma superstore_refl :
  forall st,
  superstore st st
.
Proof.
  intro st.
  unfold superstore.
  trivial.
Qed.

Lemma superstore_trans :
  forall st1 st2 st3,
  superstore st1 st2 ->
  superstore st2 st3 ->
  superstore st1 st3
.
Proof.
  intros st1 st2 st3 H_1_2 H_2_3.
  unfold superstore.
  unfold superstore in H_1_2.
  unfold superstore in H_2_3.
  intros loc H_1.
  apply H_2_3.
  apply H_1_2.
  apply H_1.
Qed.

(******** Consistency of Store operations ********)

Lemma get_loc_returns_valid_loc :
  forall st name,
  all_locs_exist st ->
  ok_loc_option st (get_loc st name)
.
Proof.
  intros st name IH.
  unfold get_loc.
    rewrite Heap.read_option_def.
    destruct LibLogic.classicT as [in_dom|not_in_dom].
      (* If the name has been found. *)
      simpl.
      assert (binds_equiv_read_name: forall loc, (Heap.binds (loc_heap st) name loc) -> (Heap.read (loc_heap st) name = loc)).
        intros loc name_bound_to_loc.
        rewrite <- Heap.binds_equiv_read.
          apply name_bound_to_loc.

          apply in_dom.

      unfold all_locs_exist in IH.
      rewrite Heap.indom_equiv_binds in in_dom.
      destruct in_dom as (x, x_in_dom).
      assert (x_in_dom_dup: Heap.binds (loc_heap st) name x).
        apply x_in_dom.

      apply IH in x_in_dom_dup.
      specialize (binds_equiv_read_name x).
      assert (read_equals_x: Heap.read (loc_heap st) name = x).
        apply binds_equiv_read_name.
        apply x_in_dom.

      rewrite <-read_equals_x in x_in_dom_dup.
      apply x_in_dom_dup.

      (* If the name has not been found *)
      unfold ok_loc_option.
      apply I.
Qed.


Definition value_write_elimination {X : Type} (pred : Store.store -> X -> Prop) :=
  forall obj_heap val_heap loc_heap fresh_locs value_loc v_loc v,
  pred
  {|
  object_heap := obj_heap;
  value_heap := val_heap;
  Store.loc_heap := loc_heap;
  fresh_locations := fresh_locs |} value_loc ->
  pred
  {|
  object_heap := obj_heap;
  value_heap := Store.Heap.write val_heap v_loc v;
  Store.loc_heap := loc_heap;
  fresh_locations := fresh_locs |} value_loc
.

Lemma value_write_elimination_ok_loc :
  value_write_elimination ok_loc
.
Proof.
  unfold value_write_elimination.
  intros obj_heap val_heap loc_heap fresh_locs value_loc v_loc v IH.
  unfold ok_loc.
  simpl.
  unfold ok_loc in IH.
  simpl in IH.
  apply HeapUtils.write_preserves_indom.
    apply LibNat.nat_comparable.

    apply IH.
Qed.



Lemma value_write_elimination_ok_loc_option :
  value_write_elimination ok_loc_option
.
Proof.
  unfold value_write_elimination.
  intros obj_heap val_heap loc_heap fresh_locs value_loc v_loc v IH.
  unfold ok_loc_option.
  unfold ok_loc_option in IH.
  destruct value_loc.
    apply value_write_elimination_ok_loc.
    apply IH.

    auto.
Qed.


Lemma add_value_preserves_store_consistency :
  forall (st st2 : Store.store) (v : Values.value) loc,
  all_locs_exist st ->
  Store.add_value st v = (st2, loc) ->
  all_locs_exist st2
.
Proof.
  intros st st2 v loc IH st2_decl.
  unfold add_value.
  destruct st.
  destruct fresh_locations.
  unfold all_locs_exist.
  split.
    (* All locs in loc_heap exist. *)
    unfold all_locs_in_loc_heap_exist.
    intros name l H.
    unfold ok_loc.
    unfold add_value in st2_decl.
    inversion st2_decl as [(st2_def,loc_def)].
    simpl.
    tests l_eq_n: (l=n).
      rewrite Heap.indom_equiv_binds.
      exists v.
      rewrite loc_def.
      apply Heap.binds_write_eq.

      unfold all_locs_exist in IH.
      simpl in IH.
      unfold ok_loc in IH.
      simpl in IH.
      apply HeapUtils.write_preserves_indom.
        apply LibNat.nat_comparable.

        rewrite <-st2_def in H.
        simpl in H.
        unfold all_locs_in_loc_heap_exist in IH.
        unfold ok_loc in IH.
        simpl in IH.
        destruct IH as (IH_val,IH_obj).
        eapply IH_val.
        apply H.

    (* All locs as object attributes exist *)
    destruct IH as (IH_val,IH_obj).
    inversion st2_decl as [(st2_def, loc_def)].
    unfold all_locs_in_obj_heap_exist.
    simpl.
    unfold all_locs_in_obj_heap_exist in IH_obj.
    simpl in IH_obj.
    intros ptr obj H.
    unfold object_locs_exist in IH_obj.
    destruct obj.
    (* We have to destruct the conjonction in IH_obj and the one
    * in the goal, and make them match clause by clause. *)
    destruct (IH_obj ptr) with {|
    object_proto := object_proto;
    object_class := object_class;
    object_extensible := object_extensible;
    object_prim_value := object_prim_value;
    object_properties_ := object_properties_;
    object_code := object_code |}
    object_proto object_class object_extensible object_prim_value object_properties_ object_code  as (IH_obj_prot, IH_obj_2).
      apply H.

      reflexivity.

      destruct IH_obj_2 as (IH_obj_primval, IH_obj_code).
      unfold object_locs_exist.
      (* Formalities to “unpack” the object. *)
      intros proto_loc class extensible primval_opt_loc props code_opt_loc eq.
      inversion eq as [(proto_eq,class_eq,ext_eq,primval_eq,props_eq,code_eq)].
      rewrite <-proto_eq.
      rewrite <-primval_eq.
      rewrite <-code_eq.
      (* Finally, we can apply IH_obj's parts. *)
      split.
        apply value_write_elimination_ok_loc.
        apply fresh_loc_preserves_ok_loc with n.
        apply IH_obj_prot.

        split.
          apply value_write_elimination_ok_loc_option.
          apply IH_obj_primval.

          apply value_write_elimination_ok_loc_option.
          apply IH_obj_code.
Qed.

Lemma add_value_returns_existing_value_loc :
  forall (st st2 : Store.store) (v : Values.value) loc,
  all_locs_exist st ->
  Store.add_value st v = (st2, loc) ->
  ok_loc st2 loc
.
Proof.
  intros st st2 v loc IH.
  unfold add_value.
  unfold ok_loc.
  destruct st.
  destruct fresh_locations.
  intro st2_decl.
  simpl.
  rewrite Heap.indom_equiv_binds.
  exists v.
  inversion st2_decl.
  apply Heap.binds_write_eq.
Qed.

Lemma add_value_makes_superstore :
  forall st st2 v loc,
  add_value st v = (st2, loc) ->
  superstore st st2
.
Proof.
  intros st st2 v loc H.
  unfold superstore.
  intros loc0 IH.
  unfold add_value in H.
  destruct st eqn:st_exp.
  destruct fresh_locations in H.
  inversion H as [(st2_def, loc_def)].
  clear H.
  unfold ok_loc.
  apply HeapUtils.write_preserves_indom.
    apply LibNat.nat_comparable.

    unfold ok_loc in IH.
    apply IH.
Qed.

Lemma add_value_return_preserves_all_locs_exist :
  forall (st st2: Store.store) res (v : Values.value),
  all_locs_exist st ->
  Context.add_value_return st v = (st2, res) ->
  all_locs_exist st2 /\ result_value_loc_exists ok_loc st2 res
.
Proof.
  intros st st2 res v IH H.
  unfold add_value_return.
  split.
    (* Store is consistent *)
    unfold add_value_return in H.
    destruct res in H.
      (* Return *)
      assert (H_unpack: add_value st v = (st2, v0)).
        destruct (add_value st v) eqn:H'.
        inversion H.
        reflexivity.

      eapply add_value_preserves_store_consistency.
        apply IH.

        apply H_unpack.

      (* Exception *)
      destruct (add_value st v) in H.
      inversion H.

      (* Break *)
      destruct (add_value st v) in H.
      inversion H.

      (* Fail *)
      destruct (add_value st v) in H.
      inversion H.


    (* Returned location exists. *)
    destruct res eqn:v0_def.
      (* Return *)
      apply result_value_loc_exists_return.
      unfold add_value_return in H.
      assert (H_unpack: add_value st v = (st2, v0)).
        destruct (add_value st v) eqn:H'.
        inversion H.
        reflexivity.

      eapply add_value_returns_existing_value_loc.
        apply IH.

        apply H_unpack.

      (* Exception *)
      unfold add_value_return in H.
      destruct (add_value st v) in H.
      inversion H.

      (* Break *)
      unfold add_value_return in H.
      destruct (add_value st v) in H.
      inversion H.

      (* Fail *)
      unfold add_value_return in H.
      destruct (add_value st v) in H.
      inversion H.
Qed.

Lemma add_object_makes_superstore :
  forall st st2 obj loc,
  add_object st obj = (st2, loc) ->
  superstore st st2
.
Proof.
  intros st st2 obj loc st2_decl.
  unfold add_object in st2_decl.
  destruct st eqn:st_def.
  destruct fresh_locations.
  destruct fresh_locations.
  inversion st2_decl as [(st2_def,loc_def)].
  destruct st2_decl as (st2_def,loc_def) eqn:foo.
  unfold superstore.
  unfold ok_loc.
  simpl.
  intros loc0 IH.
  apply HeapUtils.write_preserves_indom.
    apply LibNat.nat_comparable.

    apply IH.
Qed.

Lemma add_object_preserves_store_consistant :
  forall st st2 obj loc,
  all_locs_exist st ->
  object_locs_exist st obj ->
  Store.add_object st obj = (st2, loc)->
  all_locs_exist st2
.
Proof.
  intros st st2 obj0 loc0 IH obj0_consistant st2_decl.
  unfold all_locs_exist.
  unfold all_locs_exist in IH.
  destruct IH as (IH_val,IH_obj).
  assert (st2_decl_copy: add_object st obj0 = (st2, loc0)).
    apply st2_decl.

  unfold add_object in st2_decl.
  destruct st eqn:st_def.
  rewrite <-st_def in st2_decl_copy.
  apply add_object_makes_superstore in st2_decl_copy.
  assert(superstore_st_st2: superstore st st2). (* For later *)
    apply st2_decl_copy.

  rewrite <-st_def in IH_val.
  rewrite <-st_def in IH_obj.
  rewrite <-st_def in obj0_consistant.
  destruct fresh_locations.
  destruct fresh_locations.
  split.
    (* We add a value in the values heap without changing the locations heap,
    * so all_locs_in_loc_heap_exist remains true. *)
    unfold all_locs_in_loc_heap_exist.
    intros name loc.
    assert (loc_heap_unchanged:
    Heap.binds (Store.loc_heap st2) name loc =
    Heap.binds (Store.loc_heap st) name loc).
      inversion st2_decl as [(st2_def, loc0_def)].
      rewrite st_def.
      simpl.
      reflexivity.

    rewrite loc_heap_unchanged.
    intro binds_name_loc.
    apply st2_decl_copy.
    unfold all_locs_in_loc_heap_exist in IH_val.
    apply IH_val with name.
    apply binds_name_loc.

    (* The values used as the object's attributes are supposed to exist,
    * so adding the object preserves all_locs_in_obj_heap_exist. *)
    unfold all_locs_in_obj_heap_exist.
    intros ptr obj obj_in_heap.
    unfold superstore in st2_decl_copy.
    unfold all_locs_in_obj_heap_exist in IH_obj.
    unfold object_locs_exist in obj0_consistant.
    unfold object_locs_exist.
    intros proto_loc class extensible primval_opt_loc props code obj_eq_obj.
    destruct obj.
    inversion obj_eq_obj as [(proto_eq,class_eq,ext_eq,primval_eq,props_eq,code_eq)].
    assert (obj_consistant: ok_loc st object_proto /\
    ok_loc_option st object_prim_value /\ ok_loc_option st object_code).
      tests obj0_eq_obj: (obj0 = {|
             object_proto := proto_loc;
             object_class := class;
             object_extensible := extensible;
             object_prim_value := primval_opt_loc;
             object_properties_ := props;
             object_code := code |}).
      apply obj0_consistant with object_class object_extensible object_properties_.
      symmetry.
      apply obj_eq_obj.

    assert (obj_in_st: Heap.binds (Store.object_heap st) ptr {|
            object_proto := proto_loc;
            object_class := class;
            object_extensible := extensible;
            object_prim_value := primval_opt_loc;
            object_properties_ := props;
            object_code := code |}).
      inversion st2_decl as [(st2_def, loc0_def)].
      clear st2_decl.
      rewrite st_def.
      simpl.
      rewrite <-obj_eq_obj.
      rewrite <-st2_def in obj_in_heap.
      simpl in obj_in_heap.
      apply HeapUtils.binds_write_inv_val_neq with n0 obj0.
        apply obj_in_heap.

        congruence. (* uses obj0_eq_obj *)

      unfold object_locs_exist in IH_obj.
      eapply IH_obj.
        apply obj_in_st.

        rewrite proto_eq.
        rewrite primval_eq.
        rewrite code_eq.
        reflexivity.

    destruct obj_consistant as (ok_loc_proto, obj_consistant2).
    destruct obj_consistant2 as (ok_loc_primval, ok_loc_code).
    split.
      apply superstore_st_st2.
      rewrite <-proto_eq.
      apply ok_loc_proto.

      split.
        eapply superstore_ok_loc_option in superstore_st_st2.
          apply superstore_st_st2.

          rewrite <-primval_eq.
          apply ok_loc_primval.

        eapply superstore_ok_loc_option in superstore_st_st2.
          apply superstore_st_st2.

          rewrite <-code_eq.
          apply ok_loc_code.
Qed.

Lemma add_object_preserves_all_locs_exist :
  forall st st2 obj loc,
  all_locs_exist st ->
  object_locs_exist st obj ->
  Store.add_object st obj = (st2, loc) ->
  all_locs_exist st2 /\ ok_loc st2 loc
.
Proof.
  intros st st2 obj loc IH obj_consistant st2_decl.
  split.
    apply add_object_preserves_store_consistant with st obj loc.
      apply IH.

      apply obj_consistant.

      apply st2_decl.

    unfold add_object in st2_decl.
    destruct st.
    destruct fresh_locations.
    destruct fresh_locations.
    inversion st2_decl as [(st2_def,loc_def)].
    unfold ok_loc.
    simpl.
    rewrite Heap.indom_equiv_binds.
    exists (Object n0).
    apply Heap.binds_write_eq.
Qed.



(******** Consistency of monads ********)

Lemma monad_ec_preserves_props :
  forall X runs st st2 e (cont : Store.store -> Context.result -> (Store.store * @Context.result X)) res2 P,
  runs_type_eval_preserves_all_locs_exist runs ->
  all_locs_exist st ->
  (forall st0 res0 st1 res1,
    superstore st st0 ->
    all_locs_exist st0 /\ result_value_loc_exists ok_loc st0 res0 ->
    cont st0 res0 = (st1, res1) ->
    superstore st0 st1 /\ P st1 res1) ->
  Monads.eval_cont runs st e cont = (st2, res2) ->
  superstore st st2 /\ P st2 res2
.
Proof.
  intros X runs st st2 e cont res2 P runs_cstt IH cont_consistant st2_decl.
  unfold Monads.eval_cont in st2_decl.
  destruct (runs_type_eval runs st e) eqn:s_decl.
  split.
    apply superstore_trans with s.
      unfold runs_type_eval_preserves_all_locs_exist in runs_cstt.
      forwards :runs_cstt.
        apply s_decl.

        apply H.
        
      unfold runs_type_eval_preserves_all_locs_exist in runs_cstt.
      apply (cont_consistant s r st2 res2).
        apply (runs_cstt st e s r).
        apply s_decl.

        apply (runs_cstt st e s r).
        apply s_decl.

        apply st2_decl.

  apply (cont_consistant s r st2 res2).
    apply (runs_cstt st e s r).
    apply s_decl.

    unfold runs_type_eval_preserves_all_locs_exist in runs_cstt.
    apply (runs_cstt st e s r).
    apply s_decl.

    apply st2_decl.
Qed.

Lemma monad_ect_preserves_all_locs_exist :
  forall runs st st2 e res2,
  runs_type_eval_preserves_all_locs_exist runs ->
  all_locs_exist st ->
  Monads.eval_cont_terminate runs st e = (st2, res2) ->
  all_locs_exist st2 /\ result_value_loc_exists ok_loc st2 res2
.
Proof.
  intros runs st st2 e res2 runs_cstt IH st2_decl.
  unfold Monads.eval_cont_terminate in st2_decl.
  eapply (monad_ec_preserves_props Values.value_loc runs st st2 e (fun (store : store) (res : result) => (store, res)) res2).
    apply runs_cstt.

    apply IH.

    intros st0 res0 st1 res1 H1 H2 eq.
    inversion eq as [(st_eq, res_eq)].
    rewrite <-st_eq.
    rewrite <-res_eq.
    split.
      apply superstore_refl.

      apply H2.

    apply st2_decl.
Qed.

Lemma monad_ir_preserves_props_loc :
  forall st st2 res (cont : Values.value_loc -> (Store.store * (@Context.result Values.value_loc))) res2 (P : Store.store -> Context.result -> Prop),
  all_locs_exist st ->
  result_value_loc_exists ok_loc st res ->
  (forall v, res = Exception v -> P st res) ->
  (forall b v, res = Break b v -> P st res) ->
  (forall f, res = Fail f -> P st res) ->
  (forall loc st1 res,
    ok_loc st loc ->
    cont loc = (st1, res) ->
    superstore st st1 /\ P st1 res) ->
  Monads.if_return st res cont = (st2, res2) ->
  superstore st st2 /\ P st2 res2
.
Proof.
  intros st st2 res cont res2 P IH H_res H_exc H_brk H_fail H st2_decl.
  unfold Monads.if_return in st2_decl.
  destruct res eqn:res_def; inversion st2_decl as [(st2_def, res2_def)].
    apply H with v.
      inversion H_res.
      assumption.

      apply st2_decl.

    rewrite <-st2_def.
    split.
      apply superstore_refl.

      apply (H_exc v).
      reflexivity.

    rewrite <-st2_def.
    split.
      apply superstore_refl.

      apply (H_brk s v).
      reflexivity.

    rewrite <-st2_def.
    split.
      apply superstore_refl.

      apply (H_fail s).
      reflexivity.
Qed.

Lemma monad_ir_preserves_props_props :
  forall st st2 res (cont : Values.object_properties -> (Store.store * (@Context.result Values.value_loc))) res2 (P : Store.store -> Context.result -> Prop),
  all_locs_exist st ->
  Logic.True -> (* TODO: write a predicate meaning that properties contain only existing locations. *)
  (forall v, res = Exception v -> P st res) ->
  (forall b v, res = Break b v -> P st res) ->
  (forall f, res = Fail f -> P st res) ->
  (forall props st1 res,
    Logic.True -> (* TODO: see above *)
    cont props = (st1, res) ->
    superstore st st1 /\ P st1 res) ->
  Monads.if_return st res cont = (st2, res2) ->
  superstore st st2 /\ P st2 res2
.
Admitted.

Lemma monad_ier_preserves_props :
  forall X runs st st2 e (cont : Store.store -> Values.value_loc -> (Store.store * @Context.result X)) loc2 (P : Store.store -> @Context.result X -> Prop),
  runs_type_eval_preserves_all_locs_exist runs ->
  all_locs_exist st ->
  (forall st0 loc0 st1 res,
    superstore st st0 ->
    all_locs_exist st0 /\ ok_loc st0 loc0 ->
    cont st0 loc0 = (st1, res) ->
    superstore st0 st1 /\ P st1 res) ->
  Monads.if_eval_return runs st e cont = (st2, loc2) ->
  superstore st st2 /\ P st2 loc2
.
Proof.
  intros X runs st st2 e cont res P.
  intros runs_cstt IH H H_res.
  unfold Monads.if_eval_return in H_res.
Admitted.
      

Lemma monad_iseren_preserves_props :
  forall X runs st st2 opt (cont : Store.store -> option Values.value_loc -> (Store.store * @Context.result X)) res2 P,
  runs_type_eval_preserves_all_locs_exist runs->
  all_locs_exist st ->
  (forall st0 oloc0 st1 res,
    superstore st st0 ->
    all_locs_exist st0 ->
    ok_loc_option st0 oloc0 ->
    cont st0 oloc0 = (st1, res) ->
    superstore st0 st1 /\ P st1 res) ->
  Monads.if_some_eval_return_else_none runs st opt cont = (st2, res2) ->
  superstore st st2 /\ P st2 res2
.
Proof.
  intros X runs st st2 opt cont res2 P runs_cstt IH H H_res.
  destruct opt.
    unfold Monads.if_some_eval_return_else_none in H_res.
    apply monad_ier_preserves_props with runs e
    (fun (ctx : store) (res : value_loc) => cont ctx (Some res)).
      apply runs_cstt.

      apply IH.

      intros st' loc' st'2 res' superstore_st_st' IH' H'.
      apply H with (Some loc').
        apply superstore_st_st'.

        apply IH'.

        unfold ok_loc_option.
        apply IH'.

        apply H'.

      apply H_res.

    unfold Monads.if_some_eval_return_else_none in H_res.
    apply H with None.
      apply superstore_refl.

      apply IH.

      unfold ok_loc_option.
      trivial.

      apply H_res.
Qed.


Lemma monad_iseed_preserves_props :
  forall X runs st st2 opt default (cont : Store.store -> Values.value_loc -> (Store.store * (@Context.result X))) res2 P,
  runs_type_eval_preserves_all_locs_exist runs ->
  all_locs_exist st ->
  (forall st0 loc0 st1 res,
    superstore st st0 ->
    all_locs_exist st0 ->
    ok_loc st0 loc0 ->
    cont st0 loc0 = (st1, res) ->
    superstore st0 st1 /\ P st1 res) ->
  Monads.if_some_eval_else_default runs st opt default cont = (st2, res2) ->
  superstore st st2 /\ P st2 res2
.
Admitted.

(******** Consistency of evaluators ********)

Lemma eval_id_preserves_all_locs_exist :
  forall runs st name st2 res,
  runs_type_eval_preserves_all_locs_exist runs ->
  all_locs_exist st ->
  Interpreter.eval_id runs st name = (st2, res) ->
  all_locs_exist st2 /\ result_value_loc_exists ok_loc st2 res
.
Proof.
  intros runs st name st2 res runs_cstt IH.
  unfold eval_id.
  destruct (get_loc st name) as [l|l] eqn: l_def.
    (* If the name exists *)
    split.
      (* Store is unchanged, so it is still consistent. *)
      inversion H as [(st2_def,res_def)].
      rewrite <-st2_def.
      apply IH.

      (* Proof that we return an existing location. *)
      inversion H as [(st2_def,res_def)].
      apply result_value_loc_exists_return.
      unfold all_locs_exist in IH.
      destruct IH as (IH_val,IH_obj).
      unfold all_locs_in_loc_heap_exist in IH_val.
      rewrite <-st2_def.
      apply (IH_val name).
      rewrite Heap.binds_equiv_read_option.
      unfold get_loc in l_def.
      apply l_def.

    (* If the name does not exist. *)
    split.
      (* Store is unchanged. *)
      inversion H as [(st2_def,res_def)].
      rewrite <-st2_def.
      apply IH.

      (* We are not returning a location, it this is consistent. *)
      inversion H.
      apply result_value_loc_exists_fail.
Qed.

Lemma eval_object_properties_preserves_ok_loc :
  forall runs st st2 props props2 loc,
  ok_loc st loc ->
  eval_object_properties runs st props = (st2, props2) ->
  ok_loc st2 loc
.
Admitted.

Lemma eval_object_properties_preserves_ok_loc_option :
  forall runs st st2 props props2 loc,
  ok_loc_option st loc ->
  eval_object_properties runs st props = (st2, props2) ->
  ok_loc_option st2 loc
.
Admitted.

Lemma eval_object_properties_preserves_all_locs_exist :
  forall runs st st2 props props2,
  all_locs_exist st ->
  eval_object_properties runs st props = (st2, props2) ->
  superstore st st2 /\ all_locs_exist st2 /\ result_value_loc_exists ignore_loc st2 props2
.
Admitted.

(* TODO: We will have to prove the added locations exist too… *)
Lemma eval_objectdecl_preserves_all_locs_exist :
  forall runs st st2 attrs props res,
  runs_type_eval_preserves_all_locs_exist runs ->
  all_locs_exist st ->
  Interpreter.eval_object_decl runs st attrs props = (st2, res) ->
  all_locs_exist st2 /\ result_value_loc_exists ok_loc st2 res
.
Proof.
  Definition pred := fun st res => all_locs_exist st /\ result_value_loc_exists ok_loc st res.
  intros runs st st2 attrs props res runs_cstt IH.
  unfold eval_object_decl.
  destruct attrs as (primval_opt_expr,value_opt_expr,prototype_opt_expr,class,extensible).
  apply monad_iseren_preserves_props with (P:=pred).
    apply runs_cstt.

    apply IH.

    intros st0 primval_oloc st1 res0 superstore_st_st0 st0_consistant ok_loc_oloc0 H.
    destruct (add_value st0 Undefined) as (store0,proto_default) eqn:store_def.
    assert (H': superstore store0 st1 /\
    all_locs_exist st1 /\ result_value_loc_exists ok_loc st1 res0).
      apply (monad_iseed_preserves_props Values.value_loc runs store0 st1 prototype_opt_expr proto_default
      (fun (store : store) (prototype_loc : value_loc) =>
       Monads.if_some_eval_return_else_none runs store value_opt_expr
         (fun (store1 : Store.store) (code : option value_loc) =>
          let (store2, props0) := eval_object_properties runs store1 props in
          Monads.if_return store2 props0
            (fun props1 : object_properties =>
             let (store3, loc) :=
                 add_object store2
                   {|
                   object_proto := prototype_loc;
                   object_class := class;
                   object_extensible := extensible;
                   object_prim_value := primval_oloc;
                   object_properties_ := props1;
                   object_code := code |} in
             (store3, Return loc))))
      ) with (P:=fun st res => all_locs_exist st /\ result_value_loc_exists ok_loc st res).
        apply runs_cstt.

        apply add_value_preserves_store_consistency in store_def.
        apply store_def.
        apply st0_consistant.

        intros st3 proto_loc st4 res1 superstore_store0_st3 st3_consistant ok_loc_proto_loc H'.
        Check monad_iseren_preserves_props.
        apply (monad_iseren_preserves_props Values.value_loc runs st3 st4 value_opt_expr
        (fun (store1 : Store.store) (code : option value_loc) =>
          let (store2, props0) := eval_object_properties runs store1 props in
          Monads.if_return store2 props0
            (fun props1 : object_properties =>
             let (store3, loc) :=
                 add_object store2
                   {|
                   object_proto := proto_loc;
                   object_class := class;
                   object_extensible := extensible;
                   object_prim_value := primval_oloc;
                   object_properties_ := props1;
                   object_code := code |} in
             (store3, Return loc)))
        ) with (P:=pred).
          apply runs_cstt.

          apply st3_consistant.

          intros st5 code_oloc st6 res2 superstore_st3_st5 st5_consistant ok_loc_code_oloc H''.
          destruct (eval_object_properties runs st5 props) as (store1, props0) eqn:store_def2.
          assert (store1_consistant: all_locs_exist store1).
            eapply eval_object_properties_preserves_all_locs_exist with (st:=st5).
              apply st5_consistant.

              apply store_def2.
          assert (props0_consistant: result_value_loc_exists ignore_loc store1 props0).
            apply eval_object_properties_preserves_all_locs_exist with runs st5 props.
              apply st5_consistant.

              apply store_def2.


          Check monad_ir_preserves_props_props.
          eapply (monad_ir_preserves_props_props st5 st6 res2
          (fun props1 : object_properties =>
            let (store3, loc) :=
                add_object store1
                  {|
                  object_proto := proto_loc;
                  object_class := class;
                  object_extensible := extensible;
                  object_prim_value := primval_oloc;
                  object_properties_ := props1;
                  object_code := code_oloc |} in
            (store3, Return loc))
            ) with (P:=pred).
            apply st5_consistant.

            Focus 2.

            intros v H_v.
            split.
              apply st5_consistant.

              rewrite H_v.

            rewrite <-H_v.
            assert (pred2:=superstore 
            apply monad_iseren_preserves_props.
            apply H''.

            intros st7 loc0 st8 res3 superstore_st5_st7 st7_consistant ok_loc_loc0 foo.

            Focus 2.

            apply H'.

            Focus 2.

            eapply H.

            apply props0_consistant.

            intros res3 st7 res4.
            destruct (add_object store1
              {|
              object_proto := proto_loc;
              object_class := class;
              object_extensible := extensible;
              object_prim_value := primval_oloc;
              object_properties_ := res3;
              object_code := code_oloc |}) as (store2,obj_loc) eqn:st3_def.
            assert (obj_consistant: object_locs_exist store1 {|
            object_proto := proto_loc;
            object_class := class;
            object_extensible := extensible;
            object_prim_value := primval_oloc;
            object_properties_ := res3;
            object_code := code_oloc |}).

              unfold object_locs_exist.
              intros proto_loc0 class0 extensible0 primval_opt_loc props1 code_opt_loc H0.
              inversion H0 as [(proto_eq,class_eq,ext_eq,primval_eq,props_eq,code_eq)].
              clear H0.
              rewrite <-proto_eq, <-primval_eq, <-code_eq.
              split.
                apply eval_object_properties_preserves_ok_loc with runs st5 props props0.
                  apply superstore_st3_st5.
                  apply ok_loc_proto_loc.
                apply store_def2.

                split.
                  apply eval_object_properties_preserves_ok_loc_option with runs st5 props props0.
                  apply superstore_ok_loc_option with st3.
                    apply superstore_st3_st5.

                    apply superstore_ok_loc_option with store0.
                      apply superstore_store0_st3.

                      assert (superstore_st0_store0: superstore st0 store0).
                        apply add_value_makes_superstore with Undefined proto_default.
                        apply store_def.

                      apply superstore_ok_loc_option with st0.
                      apply superstore_st0_store0.
                      apply ok_loc_oloc0.

              apply store_def2.

              apply eval_object_properties_preserves_ok_loc_option with runs st5 props props0.
                apply ok_loc_code_oloc.

                apply store_def2.

            split.

              eapply add_object_preserves_store_consistant with (obj := {|
              object_proto := proto_loc;
              object_class := class;
              object_extensible := extensible;
              object_prim_value := primval_oloc;
              object_properties_ := res3;
              object_code := code_oloc |}).
                edestruct add_object_preserves_all_locs_exist as (store2_consistant,obj_loc_in_store2).
                  apply store1_consistant.

                  apply obj_consistant.

                  apply st3_def.

                  edestruct eval_object_properties_preserves_all_locs_exist as (store1_cstt_val,store1_cstt_obj).
                    apply st5_consistant.

                    apply store_def2.

                  apply store1_consistant.

              apply obj_consistant.

              inversion H as [(st7_def, res4_def)].
              rewrite <-st7_def.
              apply st3_def.


            inversion H as [(st7_def, res4_def)].
            rewrite <-st7_def.
            apply result_value_loc_exists_return.
            eapply add_object_preserves_all_locs_exist.
              apply store1_consistant.

              apply obj_consistant.

              apply st3_def.
Qed.


(******** Conclusions *********)

Theorem eval_preserves_all_locs_exist :
  forall runs (st st2 : Store.store) res,
  forall st (e : Syntax.expression),
  runs_type_eval_preserves_all_locs_exist runs ->
  all_locs_exist st ->
  Interpreter.eval runs st e = (st2, res) ->
  all_locs_exist st2 /\ result_value_loc_exists ok_loc st2 res
.
Proof.
  intros runs st st2 res st0 e IH H.
  destruct e; unfold eval; simpl;
    (* Null, Undefined, String, Number, True, False. *)
    try solve [apply add_value_return_preserves_all_locs_exist; apply H].

    (* Id *)
    applys* eval_id_preserves_all_locs_exist.

    (* ObjectDecl *)
    applys* eval_objectdecl_preserves_all_locs_exist.

Admitted.

Theorem runs_preserves_all_locs_exist :
  forall max_steps (st : Store.store),
  forall runner st (e : Syntax.expression),
  all_locs_exist st ->
  let (st2, res) := Interpreter.runs runner max_steps st e in
  all_locs_exist st2 /\ result_value_loc_exists ok_loc st2 res
.
Admitted.
