Require Import Coq.ZArith.ZArith Coq.Lists.List Coq.Strings.String Coq.Sets.Ensembles Coq.Classes.Morphisms.
Require Import compcert.lib.Maps compcert.lib.Coqlib.
Require Import L6.cps L6.state L6.freshen L6.cps_util L6.cps_show L6.ctx L6.hoare L6.inline L6.rename L6.identifiers
        L6.Ensembles_util L6.alpha_conv L6.functions L6.logical_relations L6.tactics L6.eval L6.map_util.
Require Import Common.compM Common.Pipeline_utils Libraries.CpdtTactics Libraries.maps_util.
Require Import ExtLib.Structures.Monad.
Require Import ExtLib.Structures.MonadState.
Require Import ExtLib.Data.Monads.StateMonad.
Require Import Coq.Structures.OrdersEx.

Import MonadNotation.
Import ListNotations.
Open Scope monad_scope.
Open Scope ctx_scope.
Open Scope fun_scope.

Section Inline_Eq.
  
  Context (St : Type) (IH : InlineHeuristic St).

  Definition beta_contract_fundefs (d : nat) (sig sig' : subst) (fm' : fun_map) :=
    (fix beta_contract_fds (fds:fundefs) (s:St) : inlineM fundefs :=
       match fds with
       | Fcons f t xs e fds' =>
         let s' := update_inFun _ IH f t xs e sig s in
         let f' := apply_r sig' f in
         xs' <- get_names_lst xs "" ;;
         e' <- beta_contract _ IH d e (set_list (combine xs xs') sig') fm' s' ;;
         fds'' <- beta_contract_fds fds' s ;;
         ret (Fcons f' t xs' e' fds'')
       | Fnil => ret Fnil
       end).
  
  Definition beta_contract' (d : nat) (e : exp) (sig : r_map) (fm:fun_map) (s:St) : inlineM exp :=
    match e with
    | Econstr x t ys e =>
      let ys' := apply_r_list sig ys in
      x' <- get_name x "" ;;
      e' <- beta_contract _ IH d e (M.set x x' sig) fm s;;
      ret (Econstr x' t ys' e')
    | Ecase v cl =>
      let v' := apply_r sig v in
      cl' <- (fix beta_list (br: list (ctor_tag*exp)) : inlineM (list (ctor_tag*exp)) :=
                match br with
                | nil => ret ( nil)
                | (t, e)::br' =>
                  e' <- beta_contract _ IH d e sig fm s;;
                  br'' <- beta_list br';;
                  ret ((t, e')::br'')
                end) cl;;
      ret (Ecase v' cl')
    | Eproj x t n y e =>
      let y' := apply_r sig y in
      x' <- get_name x "" ;;
      e' <- beta_contract _ IH d e (M.set x x' sig) fm s;;
      ret (Eproj x' t n y' e')
    | Eletapp x f t ys ec =>
      let f' := apply_r sig f in
      let ys' := apply_r_list sig ys in
      let (s' , inl) := update_letApp _ IH f' t ys' s in
      (match (inl, M.get f fm, d) with
       | (true, Some (t, xs, e), S d') =>
         let sig' := set_list (combine xs ys') sig  in            
         e' <- beta_contract _ IH d' e sig' fm s' ;;
         match inline_letapp e' x, Nat.eqb (List.length xs) (List.length ys) with
         | Some (C, x'), true =>
           ec' <- beta_contract _ IH d' ec (M.set x x' sig) fm s' ;;
           ret (C |[ ec' ]|)
         | _, _ =>
           x' <- get_name x "" ;;
           ec' <- beta_contract _ IH d ec (M.set x x' sig) fm s' ;;
           ret (Eletapp x' f' t ys' ec')
         end
       | _ =>
         x' <- get_name x "" ;;
         ec' <- beta_contract _ IH d ec (M.set x x' sig) fm s' ;;
         ret (Eletapp x' f' t ys' ec')
       end)
    | Efun fds e =>
      let fm' := add_fundefs fds fm in
      let (s1, s2) := update_funDef _ IH fds sig s in
      let names := all_fun_name fds in
      names' <- get_names_lst names "" ;;
      let sig' := set_list (combine names names') sig in
      fds' <-  beta_contract_fundefs d sig sig' fm' fds s2 ;;
      e' <- beta_contract _ IH d e sig' fm' s1;;
      ret (Efun fds' e')
    | Eapp f t ys =>
      let f' := apply_r sig f in
      let ys' := apply_r_list sig ys in
      let (s', inl) := update_App _ IH f' t ys' s in
      (match (inl, M.get f fm, d) with
       | (true, Some (ft, xs, e), S d') =>
         if Nat.eqb (List.length xs) (List.length ys) then
           let sig' := set_list (combine xs ys') sig  in
           beta_contract _ IH d' e sig' fm  s'
         else ret (Eapp f' t ys')
       | _ => ret (Eapp f' t ys')
       end)
    | Eprim x t ys e =>
      let ys' := apply_r_list sig ys in
      x' <- get_name x "" ;;
      e' <- beta_contract _ IH d e (M.set x x' sig) fm s;;
      ret (Eprim x' t ys' e')
    | Ehalt x =>
      let x' := apply_r sig x in
      ret (Ehalt x')
    end.
  
  
  Lemma beta_contract_eq (d : nat) (e : exp) (sig : r_map) (fm:fun_map) (s:St) : 
    beta_contract _ IH d e sig fm s = beta_contract' d e sig fm s.
  Proof.
    destruct d; destruct e; try reflexivity.
  Qed.

End Inline_Eq. 

Opaque bind ret.


Definition Range (x1 x2 : positive) : Ensemble var := fun z => x1 <= z < x2.

Lemma Disjoint_Range (x1 x2 x1' x2' : positive) :
  x2 <= x1' ->
  Disjoint _ (Range x1 x2) (Range x1' x2').
Proof.
  intros Hleq. constructor. intros x Hin. inv Hin.
  unfold Range, Ensembles.In in *. simpl in *. zify. omega.
Qed.    

Lemma Range_Subset (x1 x2 x1' x2' : positive) :
  x1 <= x1' ->
  x2' <= x2 ->
  Range x1' x2' \subset Range x1 x2.
Proof.
  intros H1 H2. intros z Hin. unfold Range, Ensembles.In in *.
  inv Hin. zify. omega.
Qed.
        
  
Lemma fresh_Range S (x1 x2 : positive) :
  fresh S x1 ->
  Range x1 x2 \subset S.
Proof.
  intros Hin z Hin'. inv Hin'. eapply Hin. eassumption.
Qed.

(** Spec for [get_name] *)
Lemma get_name_fresh A S y str :
  {{ fun _ (s : comp_data * A) => fresh S (next_var (fst s)) }}
    get_name y str
  {{ fun (r: unit) s x s' =>
       x \in Range (next_var (fst s)) (next_var (fst s')) /\
       (next_var (fst s) < next_var (fst s')) /\
       fresh (S \\ [set x]) (next_var (fst s'))      
  }}.  
Proof. 
  eapply pre_post_mp_l.
  eapply bind_triple. now eapply get_triple.  
  intros [[] w1] [[] w2].
  eapply pre_post_mp_l. simpl.
  eapply bind_triple. now eapply put_triple.
  intros x [r3 w3].
  eapply return_triple. 
  intros ? [r4 w4] H2. inv H2. intros [H1 H2]. inv H1; inv H2. intros.
  split. simpl. unfold Range, Ensembles.In. zify. omega.
  simpl. split. zify; omega.
  intros z Hin. constructor. eapply H; eauto. zify. omega.
  intros Hc. inv Hc. zify; omega.
Qed.

Lemma get_names_lst_fresh A S ns str :
  {{ fun _ (s : comp_data * A) => fresh S (next_var (fst s)) }}
    get_names_lst ns str
  {{ fun (r: unit) s xs s' =>
       NoDup xs /\ List.length xs = List.length ns /\
       FromList xs \subset Range (next_var (fst s)) (next_var (fst s')) /\
       (next_var (fst s) <= next_var (fst s')) /\
       fresh (S \\ FromList xs) (next_var (fst s')) }}.  
Proof.
  unfold get_names_lst. revert S; induction ns; intros S.
  - simpl. eapply return_triple.
    intros. repeat normalize_sets. split; eauto. sets. now constructor. split; eauto.
    split. now sets. split. reflexivity. eassumption.
  - simpl. eapply bind_triple. eapply get_name_fresh.
    intros x w.
    eapply bind_triple. eapply frame_rule. eapply frame_rule. eapply IHns.
    intros xs w'. eapply return_triple. intros. destructAll.
    repeat normalize_sets. split; [| split; [| split; [| split ]]].
    + constructor; eauto. intros Hc. eapply H3 in Hc. 
      eapply Disjoint_Range; [| constructor; [ eapply H | eapply Hc ] ]. reflexivity.
    + simpl. omega.
    + eapply Union_Included. eapply Singleton_Included.
      eapply Range_Subset; [| | eassumption ]. reflexivity. zify. omega.
      eapply Included_trans. eassumption. eapply Range_Subset. zify; omega. reflexivity.
    + zify; omega.
    + rewrite <- Setminus_Union. eassumption.
Qed.

Fixpoint funname_in_exp (e : exp) : Ensemble var :=
  match e with
  | Econstr _ _ _ e
  | Eproj _ _ _ _ e
  | Eletapp _ _ _ _ e
  | Eprim _ _ _ e => funname_in_exp e
  | Ecase _ P =>
    (fix aux P :=
       match P with
       | [] => Empty_set _
       | (c, e) :: P => funname_in_exp e :|: aux P
       end) P      
  | Efun B e => funname_in_fundefs B :|: name_in_fundefs B :|: funname_in_exp e
  | Eapp _ _ _ 
  | Ehalt _ => Empty_set _
  end
with funname_in_fundefs (B : fundefs) : Ensemble var :=
       match B with
       | Fcons _ _ _ e B => funname_in_exp e :|: funname_in_fundefs B
       | Fnil => Empty_set var
       end.

Fixpoint funfv_in_exp (e : exp) : Ensemble var :=
  match e with
  | Econstr _ _ _ e
  | Eproj _ _ _ _ e
  | Eletapp _ _ _ _ e
  | Eprim _ _ _ e => funfv_in_exp e
  | Ecase _ P =>
    (fix aux P :=
       match P with
       | [] => Empty_set _
       | (c, e) :: P => funfv_in_exp e :|: aux P
       end) P      
  | Efun B e => occurs_free_fundefs B :|: funfv_in_fundefs B :|: funfv_in_exp e
  | Eapp _ _ _ 
  | Ehalt _ => Empty_set _
  end
with funfv_in_fundefs (B : fundefs) : Ensemble var :=
       match B with
       | Fcons _ _ _ e B => funfv_in_exp e :|: funfv_in_fundefs B
       | Fnil => Empty_set var
       end.

  
Section Inline_correct.

  Context (St : Type) (IH : InlineHeuristic St) (cenv : ctor_env) (P1 : PostT) (PG : PostGT).


  Variable (HPost_con : post_constr_compat P1 P1)
           (HPost_proj : post_proj_compat P1 P1)
           (HPost_fun : post_fun_compat P1 P1)
           (HPost_case_hd : post_case_compat_hd P1 P1)
           (HPost_case_tl : post_case_compat_tl P1 P1)
           (HPost_app : post_app_compat P1 PG)
           (HPost_letapp : post_letapp_compat cenv P1 P1 PG)
           (HPost_letapp_OOT : post_letapp_compat_OOT P1 PG)
           (HPost_OOT : post_OOT P1)
           (Hpost_base : post_base P1)
           (HGPost : inclusion P1 PG)
           (Hpost_zero : forall e rho, post_zero e rho P1).

           (* (HPost_conG : post_constr_compat PG PG) *)
           (* (HPost_projG : post_proj_compat PG PG) *)
           (* (HPost_funG : post_fun_compat PG PG) *)
           (* (HPost_case_hdG : post_case_compat_hd PG PG) *)
           (* (HPost_case_tlG : post_case_compat_tl PG PG) *)
           (* (HPost_appG : post_app_compat PG PG) *)
           (* (HPost_letappG : post_letapp_compat cenv PG PG PG) *)
           (* (HPost_letapp_OOTG : post_letapp_compat_OOT PG PG) *)
           (* (HPost_OOTG : post_OOT PG) *)
           (* (Hpost_baseG : post_base PG) *)
           (* (Hless_steps_letapp : remove_steps_letapp cenv P1 P1 P1) *)
           (* (Hless_steps_letapp' : remove_steps_letapp' cenv P1 P1 P1) *)
           (* (Hless_steps_letapp_OOT : remove_steps_letapp_OOT cenv P1 P1) *)
           (* (Hless_steps_letapp_OOT' : remove_steps_letapp_OOT' cenv P1 P1) *)
           (* (Hpost_zero : forall e rho, post_zero e rho P1). *)

  Definition fun_map_fv (fm : fun_map) : Ensemble var :=
    fun v => exists f ft xs e, fm ! f = Some (ft, xs, e) /\ v \in occurs_free e.

  Definition fun_map_bv (fm : fun_map) : Ensemble var :=
    fun v => exists f ft xs e, fm ! f = Some (ft, xs, e) /\ v \in bound_var e.

  Definition funs_in_env (rho : env) : Ensemble var :=
    fun v => exists r B f, rho!v = Some (Vfun r B f).

  Definition occurs_free_in_val (v : val) : Ensemble var :=
    match v with
    | Vfun rho B f => occurs_free_fundefs B :|: name_in_fundefs B
    | _ => Empty_set _
    end.

  Definition fun_bindings_val (v : val) :=
    match v with
    | Vint _
    | Vconstr _ _ => Empty_set _ 
    | Vfun rho B _ => name_in_fundefs B :|: funs_in_env rho
    end.      

  Definition fun_bindings_env (rho : env) : Ensemble var :=
    fun f => exists x v, rho!x = Some v /\ f \in fun_bindings_val v.

  Lemma fun_bindings_env_set (rho : env) x v :
    fun_bindings_env (M.set x v rho) \subset fun_bindings_val v :|: fun_bindings_env rho.
  Proof.
    intros z Hin. unfold Ensembles.In, fun_bindings_env in *.
    destructAll. destruct (peq x x0); subst.
    - rewrite M.gss in H. inv H. now left; eauto.
    - rewrite M.gso in H; eauto. right. do 2 eexists. split; eauto.
  Qed.
  
  Lemma fun_bindings_env_set_lists (rho rho' : env) xs vs :
    set_lists xs vs rho = Some rho' ->    
    fun_bindings_env rho' \subset \bigcup_(v in FromList vs) (fun_bindings_val v) :|: fun_bindings_env rho.
  Proof.
    revert rho' vs. induction xs; intros rho' vs Hset; destruct vs; try now inv Hset.
    - inv Hset. normalize_sets. rewrite big_cup_Empty_set. sets.
    - normalize_sets. rewrite Union_big_cup.
      simpl in Hset. destruct (set_lists xs vs rho) eqn:Hset'; inv Hset.
      eapply Included_trans. eapply fun_bindings_env_set.
      rewrite big_cup_Singleton. rewrite <- Union_assoc. eapply Included_Union_compat. now sets.
      eauto.
  Qed.
  
  Lemma fun_bindings_env_get (rho : env) x v :
    rho ! x = Some v ->
    fun_bindings_val v \subset fun_bindings_env rho.
  Proof.
    intros Hget z Hin. do 2 eexists. split. eassumption. eassumption.
  Qed.

  Lemma fun_bindings_env_get_list (rho : env) xs vs :
    get_list xs rho = Some vs ->
    \bigcup_(v in FromList vs) (fun_bindings_val v) \subset fun_bindings_env rho.
  Proof.
    revert vs. induction xs; intros vs Hget.
    - destruct vs; try now inv Hget. normalize_sets. rewrite big_cup_Empty_set. sets.
    - simpl in Hget. destruct (rho!a) eqn:Hgeta; try now inv Hget.
      destruct (get_list xs rho) eqn:Hgetl; try now inv Hget. inv Hget.
      normalize_sets. rewrite Union_big_cup. rewrite big_cup_Singleton.
      eapply Union_Included; eauto.
      eapply fun_bindings_env_get. eassumption.
  Qed.

  Lemma fun_bindings_env_def_funs (rho rhoc : env) B0 B :
    fun_bindings_env (def_funs B0 B rhoc rho) \subset name_in_fundefs B0 :|: funs_in_env rhoc :|: fun_bindings_env rho.
  Proof.
    revert rho; induction B; intros rho x HIn. simpl in HIn.
    - eapply fun_bindings_env_set in HIn. simpl in HIn. inv HIn; eauto.
      eapply IHB. eassumption.
    - simpl in HIn. now right.
  Qed.

  Definition occurs_free_fun_map (fm : fun_map) : Ensemble var :=
    fun x => exists f ft xs e, fm ! f = Some (ft, xs, e) /\ x \in occurs_free e \\ FromList xs.

  Definition bound_var_fun_map (fm : fun_map) : Ensemble var :=
    fun x => exists f ft xs e, fm ! f = Some (ft, xs, e) /\ x \in bound_var e \\ funname_in_exp e :|: FromList xs.


  Fixpoint fun_map_inv' (k : nat) (S : Ensemble var) (fm : fun_map) (rho1 rho2 : env) (i : nat) (sig : subst) : Prop :=
    forall f ft xs e rhoc B f',
      f \in S ->
      fm ! f = Some (ft, xs, e) ->
      rho1 ! f = Some (Vfun rhoc B f') ->
      find_def f B = Some (ft, xs, e) /\ f = f' /\
      preord_env_P_inj cenv PG (occurs_free e \\ FromList xs) i (apply_r sig) (def_funs B B rhoc rhoc) rho2 /\
      sub_map (def_funs B B rhoc rhoc) rho1 /\
      Disjoint _ (bound_var e) (Dom_map rhoc :|: name_in_fundefs B) /\
      Disjoint _ (FromList xs) (Dom_map rhoc :|: name_in_fundefs B) /\
      match k with
      | 0%nat => True
      | S k => fun_map_inv' k (occurs_free e \\ FromList xs) fm (def_funs B B rhoc rhoc) rho2 i sig
      end.

  Definition fun_map_inv (k : nat) (S : Ensemble var) (fm : fun_map) (rho1 rho2 : env) (i : nat) (sig : subst) : Prop :=
    forall f ft xs e rhoc B f',
      f \in S ->
      fm ! f = Some (ft, xs, e) ->
      rho1 ! f = Some (Vfun rhoc B f') ->
      find_def f B = Some (ft, xs, e) /\ f = f' /\
      preord_env_P_inj cenv PG (occurs_free e \\ FromList xs) i (apply_r sig) (def_funs B B rhoc rhoc) rho2 /\
      sub_map (def_funs B B rhoc rhoc) rho1 /\
      Disjoint _ (bound_var e) (Dom_map rhoc :|: name_in_fundefs B) /\
      Disjoint _ (FromList xs) (Dom_map rhoc :|: name_in_fundefs B) /\
      match k with
      | 0%nat => True
      | S k => fun_map_inv' k (occurs_free e \\ FromList xs) fm (def_funs B B rhoc rhoc) rho2 i sig
      end.

  Lemma fun_map_inv_eq k S fm rho1 rho2 n sig :
    fun_map_inv k S fm rho1 rho2 n sig = fun_map_inv' k S fm rho1 rho2 n sig.
  Proof.
    destruct k; reflexivity.
  Qed.
  
  Lemma fun_map_inv_mon k k' S fm rho1 rho2 i sig :
    fun_map_inv k S fm rho1 rho2 i sig ->
    (k' <= k)%nat ->
    fun_map_inv k' S fm rho1 rho2 i sig.
  Proof.
    revert S k fm rho1 rho2 i sig. induction k' as [k' IHk] using lt_wf_rec1; intros.
    destruct k'.
    - unfold fun_map_inv in *. intros. edestruct H; eauto. destructAll.
      repeat (split; eauto).
    - destruct k; [ omega | ].
      intro; intros. edestruct H; eauto. destructAll. 
      split; eauto. split; eauto. split; eauto. split; eauto. split; eauto. split; eauto.
      rewrite <- fun_map_inv_eq. eapply IHk. 
      omega. rewrite fun_map_inv_eq. eassumption. omega. 
  Qed.

  Lemma fun_map_inv_i_mon k S fm rho1 rho2 i i' sig :
    fun_map_inv k S fm rho1 rho2 i sig ->
    (i' <= i)%nat ->
    fun_map_inv k S fm rho1 rho2 i' sig.
  Proof.
    revert k S fm rho1 rho2 i i' sig. induction k as [k' IHk] using lt_wf_rec1; intros.
    intros. intro; intros. edestruct H; eauto. destructAll. split; eauto. split; eauto. split; eauto. 
    eapply preord_env_P_inj_monotonic; eassumption.
    split; eauto. split; eauto. split; eauto.
    destruct k'; eauto. rewrite <- fun_map_inv_eq in *. eapply IHk; eauto.
  Qed.

  Lemma fun_map_inv_antimon k S S' fm rho1 rho2 i sig :
    fun_map_inv k S fm rho1 rho2 i sig ->
    S' \subset S ->
    fun_map_inv k S' fm rho1 rho2 i sig.
  Proof.
    intros H1 H2. intro; intros; eauto.
  Qed.

  Lemma sub_map_set {A} rho x (v : A) :
    ~ x \in Dom_map rho ->
    sub_map rho (M.set x v rho).
  Proof.
    intros Hnin z1 v1 Hget1. rewrite M.gso; eauto.
    intros hc. subst. eapply Hnin. eexists; eauto.
  Qed.

  Lemma sub_map_trans {A} (rho1 rho2 rho3 : M.t A) :
    sub_map rho1 rho2 ->
    sub_map rho2 rho3 ->
    sub_map rho1 rho3.
  Proof.
    intros H1 H2 x v Hget. eauto.
  Qed.

  Lemma sub_map_refl {A} (rho : M.t A) :
    sub_map rho rho.
  Proof.
    intro; intros; eauto.
  Qed.

  (* 
  Lemma occurs_free_in_env_set rho x v :
    occurs_free_in_env (M.set x v rho) \subset occurs_free_in_val v :|: occurs_free_in_env rho.
  Proof.
    intros z [y Hin]. destructAll. destruct (peq x y); subst.
    - rewrite M.gss in H. inv H. now left; eauto.
    - rewrite M.gso in H; eauto. right.
      do 4 eexists; split; eauto.
  Qed.

  Lemma occurs_free_in_env_get rho x v :
    M.get x rho = Some v ->
    occurs_free_in_val v \subset occurs_free_in_env rho.
  Proof.
    intros Hget z Hin.
    destruct v; try now inv Hin.
    do 4 eexists; split; eauto.
  Qed.
  
  Lemma occurs_free_in_env_get_list (rho : env) xs vs :
    get_list xs rho = Some vs ->
    \bigcup_(v in FromList vs) (occurs_free_in_val v) \subset occurs_free_in_env rho.
  Proof.
    revert vs. induction xs; intros vs Hget.
    - destruct vs; try now inv Hget. normalize_sets. rewrite big_cup_Empty_set. sets.
    - simpl in Hget. destruct (rho!a) eqn:Hgeta; try now inv Hget.
      destruct (get_list xs rho) eqn:Hgetl; try now inv Hget. inv Hget.
      normalize_sets. rewrite Union_big_cup. rewrite big_cup_Singleton.
      eapply Union_Included; eauto.
      eapply occurs_free_in_env_get. eassumption.
  Qed.

  
  Lemma occurs_free_in_env_def_funs B rho:
    occurs_free_in_env (def_funs B B rho rho) \subset occurs_free_fundefs B :|: name_in_fundefs B :|: occurs_free_in_env rho.
  Proof.
    intros x1 Hin1. inv Hin1. destructAll.
    destruct (Decidable_name_in_fundefs B). destruct (Dec x).
    + rewrite def_funs_eq in H; eauto. inv H. now left; eauto.
    + rewrite def_funs_neq in H; eauto. right. eapply occurs_free_in_env_get. eassumption.
      eassumption.
  Qed.
  
  Lemma occurs_free_in_env_def_funs' B rho:
    occurs_free_fundefs B :|: name_in_fundefs B \subset occurs_free_in_env (def_funs B B rho rho).
  Proof.
    intros x Hc. destruct B.
    - eapply occurs_free_in_env_get. simpl. rewrite M.gss. reflexivity. simpl. eassumption.
    - inv Hc. inv H. inv H.
  Qed.
 
  
  Lemma sub_map_occurs_free_in_env rho1 rho2 :
    sub_map rho1 rho2 ->
    occurs_free_in_env rho1 \subset occurs_free_in_env rho2.
  Proof.
    intros Hs z Hin. inv Hin. destructAll.
    eapply Hs in H. do 4 eexists. split. eassumption. eassumption.
  Qed. *)

  Lemma add_fundefs_in fm f B ft xs e:
    find_def f B = Some (ft, xs, e) -> 
    (add_fundefs B fm) ! f = Some (ft, xs, e). 
  Proof.
    induction B.
    - simpl. intros Hdef. destruct (M.elt_eq f v); subst.
      + inv Hdef. simpl. rewrite M.gss. reflexivity.
      + simpl. rewrite M.gso; eauto.
    - intros H. inv H.
  Qed.

  Lemma add_fundefs_not_in fm f B :
    ~ f \in name_in_fundefs B -> 
            (add_fundefs B fm) ! f = fm ! f.
  Proof.
    intros Hnin. induction B.
    - simpl. rewrite M.gso. eapply IHB.
      intros Hc. eapply Hnin. simpl. now right; eauto.
      intros Hc. eapply Hnin. simpl. subst; eauto.
    - reflexivity.
  Qed.


  Lemma occurs_free_fun_map_get f ft xs e (fm : fun_map) :
    M.get f fm = Some (ft, xs, e) ->
    occurs_free e \\ (FromList xs) \subset occurs_free_fun_map fm.
  Proof.
    intros Hget z Hin. do 4 eexists. split; eauto.
  Qed.

  Lemma occurs_free_fun_map_add_fundefs B fm :
    occurs_free_fun_map (add_fundefs B fm) \subset occurs_free_fundefs B :|: name_in_fundefs B :|: occurs_free_fun_map fm.
  Proof.
    intros x [z Hin]. destructAll. destruct (Decidable_name_in_fundefs B). destruct (Dec z).
    - edestruct name_in_fundefs_find_def_is_Some. eassumption. destructAll.
      erewrite add_fundefs_in in H; eauto. inv H. left.
      eapply find_def_correct in H1. eapply occurs_free_in_fun in H1.
      inv H0. eapply H1 in H. inv H. contradiction. inv H0; eauto.
    - right. rewrite add_fundefs_not_in in H. do 4 eexists; split; eauto.
      eassumption.
  Qed. 


  Lemma fun_in_fundefs_bound_var_Setminus e f ft xs B :
    fun_in_fundefs B (f, ft, xs, e) ->
    unique_bindings_fundefs B ->
    bound_var e \\ funname_in_exp e \subset bound_var_fundefs B \\ funname_in_fundefs B.
  Proof.
    intros Hin Hun. induction B; [| now inv Hin ].
    inv Hun. simpl in Hin. inv Hin.
    - inv H. simpl. normalize_bound_var.
  Admitted.

  Lemma fun_in_fundefs_bound_var_Setminus' e f ft xs B :
    fun_in_fundefs B (f, ft, xs, e) ->
    unique_bindings_fundefs B ->
    bound_var e \\ funname_in_exp e \\ name_in_fundefs B \subset bound_var_fundefs B \\ funname_in_fundefs B.
  Proof.
    intros Hin Hun. induction B; [| now inv Hin ].
    inv Hun. simpl in Hin. inv Hin.
    - inv H. simpl. normalize_bound_var.
  Admitted.


  Lemma fun_in_fundefs_FromList_subset e f ft xs B :
    fun_in_fundefs B (f, ft, xs, e) ->
    unique_bindings_fundefs B ->
    FromList xs \subset bound_var_fundefs B \\ funname_in_fundefs B \\ name_in_fundefs B.
  Proof.
    intros Hin Hun. induction B; [| now inv Hin ]. inv Hin.
    - inv H. normalize_bound_var. simpl.
  Admitted.    

  Lemma bound_var_fun_map_get f ft xs e (fm : fun_map) :
    M.get f fm = Some (ft, xs, e) ->
    bound_var e \\ funname_in_exp e :|: (FromList xs) \subset bound_var_fun_map fm.
  Proof.
    intros Hget z Hin. do 4 eexists. split; eauto.
  Qed.


  Lemma bound_var_fun_map_add_fundefs_un B fm :
    unique_bindings_fundefs B ->
    bound_var_fun_map (add_fundefs B fm) \subset (bound_var_fundefs B \\ funname_in_fundefs B \\ name_in_fundefs B) :|: bound_var_fun_map fm.
  Proof.
    intros Hun x [z Hin]. destructAll. destruct (Decidable_name_in_fundefs B). destruct (Dec z).
    - edestruct name_in_fundefs_find_def_is_Some. eassumption. destructAll. erewrite add_fundefs_in in H; [| eassumption ]. inv H.
      edestruct unique_bindings_fun_in_fundefs. eapply find_def_correct. eassumption. eassumption. destructAll.
      left.     
      inv H0.
      + constructor. eapply fun_in_fundefs_bound_var_Setminus. eapply find_def_correct. eassumption. eassumption. eassumption.
        inv H8. intros hc. eapply H4; constructor; eauto.
      + eapply fun_in_fundefs_FromList_subset. eapply find_def_correct. eassumption. eassumption. eassumption.
    - right. rewrite add_fundefs_not_in in H. do 4 eexists; split; eauto.
      eassumption.
  Qed. 


  (* Lemma bound_var_fun_map_add_fundefs B fm : *)
  (*   bound_var_fun_map (add_fundefs B fm) \subset bound_var_fundefs B \\ funname_in_fundefs B :|: bound_var_fun_map fm. *)
  (* Proof. *)
  (*   intros x [z Hin]. destructAll. destruct (Decidable_name_in_fundefs B). destruct (Dec z). *)
  (*   - edestruct name_in_fundefs_find_def_is_Some. eassumption. destructAll. *)
  (*     erewrite add_fundefs_in in H; eauto. inv H. left. eapply fun_in_fundefs_bound_var_fundefs. *)
  (*     eapply find_def_correct. eassumption. inv H0; eauto. *)
  (*   - right. rewrite add_fundefs_not_in in H. do 4 eexists; split; eauto. *)
  (*     eassumption. *)
  (* Qed.  *)


  Lemma fun_map_inv_set_not_In_r k S fm rho1 rho2 i sig x x' v' : 
    fun_map_inv k S fm rho1 rho2 i sig ->
    ~ x \in occurs_free_fun_map fm ->
    ~ x' \in image (apply_r sig) (occurs_free_fun_map fm) ->
    fun_map_inv k S fm rho1 (M.set x' v' rho2) i (M.set x x' sig).
  Proof.
    revert S fm rho1 rho2 i sig x x' v'. induction k using lt_wf_rec1; intros. intro; intros.
    edestruct H0; eauto.
    destructAll. split; [| split; [| split; [| split; [| split; [| split ]]]]]; eauto.
    - rewrite apply_r_set_f_eq. eapply preord_env_P_inj_set_extend_not_In_P_r. eassumption.
      + intros Hc. eapply H1. eapply occurs_free_fun_map_get; eassumption.
      + intros Hc. eapply H2. eapply image_monotonic; [| eassumption ]. 
        eapply occurs_free_fun_map_get; eauto.
    - destruct k; eauto. rewrite <- fun_map_inv_eq in *.
      eapply H. omega. eassumption. eassumption. eassumption.
  Qed.                

  Lemma fun_map_inv_set k S fm rho1 rho2 i sig x v x' v' :
    fun_map_inv k S fm rho1 rho2 i sig ->
    ~ x \in Dom_map rho1 :|: Dom_map fm :|: occurs_free_fun_map fm ->
    ~ x' \in image (apply_r sig) (occurs_free_fun_map fm) ->
    fun_map_inv k (x |: S) fm (M.set x v rho1) (M.set x' v' rho2) i (M.set x x' sig).
  Proof.
    intros Hinv Hnin Hnin'. intro; intros.
    rewrite M.gso in *. 
    2:{ intros Heq; subst. eapply Hnin. left. right. eexists; eauto. }
    inv H.
    - inv H2. exfalso. eapply Hnin. left. left. eexists; eauto.
    - edestruct Hinv; eauto.
      destructAll. split; [| split; [| split; [| split; [| split; [| split ]]]]]; eauto.
      + rewrite apply_r_set_f_eq. eapply preord_env_P_inj_set_extend_not_In_P_r. eassumption.
        intros Hc. eapply Hnin. right. eapply occurs_free_fun_map_get; eassumption. simpl.
        intros Hc. eapply Hnin'. eapply image_monotonic; [| eassumption ].
        eapply occurs_free_fun_map_get; eassumption.
      + eapply sub_map_trans. eassumption. eapply sub_map_set.
        intros Hc. eapply Hnin. left. left. eassumption.
      + destruct k; eauto. rewrite <- fun_map_inv_eq in *.
        eapply fun_map_inv_set_not_In_r. eapply fun_map_inv_antimon. eassumption.
        * reflexivity.
        * intros Hc. eapply Hnin. right. eassumption.
        * intros Hc. eapply Hnin'. eapply image_monotonic; [| eassumption ]. sets.
  Qed.
  
(* 
  Lemma occurs_free_in_env_set_lists_not_In rho rho' xs vs :
    set_lists xs vs rho = Some rho' ->
    occurs_free_in_env rho' \subset \bigcup_(v in FromList vs) (occurs_free_in_val v) :|: occurs_free_in_env rho.
  Proof.
    revert rho' vs. induction xs; intros rho' vs Hset; destruct vs; try now inv Hset.
    - inv Hset. normalize_sets. rewrite big_cup_Empty_set. sets.
    - normalize_sets. rewrite Union_big_cup.
      simpl in Hset. destruct (set_lists xs vs rho) eqn:Hset'; inv Hset.
      eapply Included_trans. eapply occurs_free_in_env_set.
      rewrite big_cup_Singleton. rewrite <- Union_assoc. eapply Included_Union_compat. now sets.
      eauto.
  Qed.

  Instance fm_map_Proper k : Proper (Same_set _ ==> eq ==> eq ==> eq ==> eq ==> eq ==> iff) (fun_map_inv k).
  Proof.
    repeat (intro; intros). subst. split; intros.
    intro; intros. rewrite <- H in H1. eauto.
    intro; intros. rewrite H in H1. eauto.
  Qed.
*)
  Lemma Dom_map_set_lists {A} xs (vs : list A) rho rho' :
    set_lists xs vs rho = Some rho' ->
    Dom_map rho' <--> FromList xs :|: Dom_map rho.
  Proof.
    revert vs rho'. induction xs; intros vs rho' Hset.
    - destruct vs; inv Hset. repeat normalize_sets. reflexivity.
    - destruct vs; try now inv Hset.
      simpl in Hset. destruct (set_lists xs vs rho) eqn:Hset1; inv Hset.
      repeat normalize_sets. rewrite Dom_map_set. rewrite IHxs. now sets.
      eassumption.
  Qed.

  Lemma sub_map_set_lists {A} rho rho' xs (vs : list A) :
    set_lists xs vs rho = Some rho' ->
    NoDup xs ->
    Disjoint _ (FromList xs) (Dom_map rho) ->
    sub_map rho rho'.
  Proof.
    revert rho rho' vs; induction xs; intros rho rho' vs Hset; destruct vs; try now inv Hset.
    simpl in Hset. destruct (set_lists xs vs rho) eqn:Hset'; inv Hset.
    intros Hnd Hdis. inv Hnd. repeat normalize_sets. eapply sub_map_trans. eapply IHxs. eassumption. eassumption.
    now sets. eapply sub_map_set. intros Hc. eapply Hdis. constructor. now left.
    eapply Dom_map_set_lists in Hc; eauto. inv Hc; eauto. exfalso. contradiction.
  Qed.

  (* TODO move *)
  Lemma apply_r_set_list_f_eq xs ys sig : 
    f_eq (apply_r (set_list (combine xs ys) sig)) (apply_r sig <{ xs ~> ys }>). 
  Proof.
    revert ys sig. induction xs; intros; simpl. reflexivity.
    destruct ys. reflexivity.
    simpl. eapply Equivalence_Transitive.
    eapply apply_r_set_f_eq. eapply f_eq_extend. eauto.
  Qed.


  Lemma fun_map_inv_sig_extend_Disjoint k S fm rho1 rho2 i sig xs xs' :
    fun_map_inv k S fm rho1 rho2 i sig ->

    Disjoint _ (FromList xs) (occurs_free_fun_map fm) ->    
    
    fun_map_inv k S fm rho1 rho2 i (set_list (combine xs xs') sig).
  Proof.
    revert S fm rho1 rho2 i sig xs xs'.
    induction k using lt_wf_rec1; intros S fm rho1 rho2 i sig xs xs' Hfm Hdis1.
    intro; intros. edestruct Hfm; eauto. destructAll.
    split; eauto. split; eauto. split; [| split; [| split; [| split ]]].
    - rewrite apply_r_set_list_f_eq. 
      eapply preord_env_P_inj_extend_lst_not_In_P_r. eassumption.
      eapply Disjoint_Included_r; [| eapply Hdis1 ].
      eapply occurs_free_fun_map_get; eauto.
    - eassumption.
    - eassumption.
    - eassumption.
    - destruct k; eauto. rewrite <- fun_map_inv_eq in *. eapply H. omega.
      eassumption. sets.
  Qed.

  Lemma fun_map_inv_set_lists k S fm rho1 rho1' rho2 i sig xs vs :
    fun_map_inv k S fm rho1 rho2 i sig ->

    NoDup xs ->
    Disjoint _ (FromList xs) (Dom_map rho1 :|: Dom_map fm) ->    
    set_lists xs vs rho1 = Some rho1' ->
    
    fun_map_inv k (FromList xs :|: S) fm rho1' rho2 i sig.
  Proof.
    revert S fm rho1 rho1' rho2 i sig xs vs.
    induction k using lt_wf_rec1;
      intros S fm rho1 rho1' rho2 i sig xs vs Hfm Hnd Hdis1 Hset.
    intro f; intros.
    destruct (Decidable_FromList xs). destruct (Dec f).
    - exfalso. eapply Hdis1. constructor. eassumption. right. eexists; eauto.
    - inv H0; try contradiction. erewrite <- set_lists_not_In in H2; [| eassumption | eassumption ].
      edestruct Hfm; eauto. destructAll. split; eauto. split; eauto. split; [| split; [| split; [| split ]]].
      + assumption.
      + eapply sub_map_trans. eassumption. eapply sub_map_set_lists. eassumption. eassumption.
        eapply Disjoint_Included_r; [| eapply Hdis1 ]. sets.
      + eassumption.
      + eassumption.
      + destruct k; eauto.
  Qed.


  (* TODO move *)
  Lemma preord_env_P_inj_set_lists_not_In_P_r S k f rho1 rho2 rho2' xs vs :
    preord_env_P_inj cenv PG S k f rho1 rho2 ->
    set_lists xs vs rho2 = Some rho2' ->
    Disjoint _(FromList xs) (image f S) ->
    preord_env_P_inj cenv PG S k f rho1 rho2'.
  Proof.
    intros Henv Hnin Hnin' z Hy v' Hget.
    edestruct Henv as [v'' [Hget' Hv]]; eauto.
    eexists; split; eauto. erewrite <- set_lists_not_In. eassumption.
    eassumption. intros Hc. eapply Hnin'. constructor. eassumption.
    eapply In_image. eassumption.
  Qed.

  Lemma fun_map_inv_set_lists_r k S fm rho1 rho2' rho2 i sig xs vs :
    fun_map_inv k S fm rho1 rho2 i sig ->
    Disjoint _ (FromList xs) (image (apply_r sig) (occurs_free_fun_map fm)) ->    

    set_lists xs vs rho2 = Some rho2' ->
    
    fun_map_inv k S fm rho1 rho2' i sig.
  Proof.
    revert S fm rho1 rho2' rho2 i sig xs vs.
    induction k using lt_wf_rec1;
      intros S fm rho1 rho1' rho2 i sig xs vs Hfm Hdis1 Hset.
    intro f; intros.
    edestruct Hfm; eauto. destructAll. split; eauto. split; eauto. split; [| split; [| split; [| split ]]]; try eassumption.
    + eapply preord_env_P_inj_set_lists_not_In_P_r. eassumption. eassumption.
      eapply Disjoint_Included_r; [| eassumption ]. eapply image_monotonic. eapply occurs_free_fun_map_get. eassumption.
    + destruct k; eauto. rewrite <- fun_map_inv_eq in *.
      eapply H. omega. eassumption. eassumption. eassumption.
  Qed.

  Lemma Dom_map_add_fundefs fm B :
    Dom_map (add_fundefs B fm) <--> name_in_fundefs B :|: Dom_map fm.
  Proof.
    induction B; simpl; [| now sets ].
    rewrite Dom_map_set. rewrite IHB. sets.
  Qed.

  
  Lemma sub_map_def_funs rho B :
    Disjoint _ (name_in_fundefs B) (Dom_map rho) ->            
    sub_map rho (def_funs B B rho rho).
  Proof.
    intros Hdis x v Hget.
    rewrite def_funs_neq; eauto.
    intros Hc. eapply Hdis. constructor. eassumption. eexists. eassumption.
  Qed.

  Lemma Dom_map_def_funs B rho B' rho' :
    Dom_map (def_funs B' B rho' rho) <--> name_in_fundefs B :|: Dom_map rho. 
  Proof.
    induction B; simpl; sets.
    rewrite Dom_map_set. rewrite IHB. sets.
  Qed.

  Lemma Dom_map_sub_map {A : Type} (rho1 rho2 : M.t A) :
    sub_map rho1 rho2 ->
    Dom_map rho1 \subset Dom_map rho2.
  Proof.
    intros H1 x [y Hin]. eapply H1 in Hin.
    eexists; eauto.
  Qed.

  Lemma fun_map_inv_add_fundefs_Disjoint k S fm rho1 rho2 i sig B1 B2 :
    fun_map_inv k S fm rho1 rho2 i sig ->
    
    Disjoint _ (name_in_fundefs B1) (S :|: Dom_map rho1 :|: occurs_free_fun_map fm) ->
    Disjoint _ (name_in_fundefs B2) (image (apply_r sig) (occurs_free_fun_map fm)) ->

    fun_map_inv k S (add_fundefs B1 fm) rho1 (def_funs B2 B2 rho2 rho2) i
                (set_list (combine (all_fun_name B1) (all_fun_name B2)) sig).
  Proof.
    revert S fm rho1 rho2 i sig B1 B2; induction k using lt_wf_rec1; intros.
    intro; intros. rewrite add_fundefs_not_in in H4.
    edestruct H0; eauto. destructAll.
    repeat (split; [ now eauto |]). split; [| split; [| split; [| split ]]].
    - eapply preord_env_P_inj_def_funs_neq_r.
      rewrite apply_r_set_list_f_eq. eapply preord_env_P_inj_extend_lst_not_In_P_r.
      eassumption. rewrite <- Same_set_all_fun_name.
      eapply Disjoint_Included_r. eapply occurs_free_fun_map_get. eassumption. sets.
      rewrite apply_r_set_list_f_eq. eapply Disjoint_Included_l.
      intros x Hc. destruct Hc. destructAll.
      rewrite extend_lst_gso. eapply In_image. eassumption.
      rewrite <- Same_set_all_fun_name. intros Hc. eapply H1. constructor. eassumption.
      right. eapply occurs_free_fun_map_get. eassumption. eassumption.
      eapply Disjoint_sym. eapply Disjoint_Included_r; [| eassumption ]. eapply image_monotonic.
      eapply occurs_free_fun_map_get. eassumption. 
    - eassumption.
    - eassumption.
    - sets.
    - destruct k; eauto. rewrite <- fun_map_inv_eq in *. eapply H. 
      + omega.
      + eassumption.
      + eapply Disjoint_Included_r; [| eassumption ]. eapply Union_Included. eapply Union_Included.
        * eapply Included_trans. eapply occurs_free_fun_map_get. eassumption. sets.
        * eapply Included_trans. eapply Dom_map_sub_map. eassumption. sets.
        * sets.
      + sets.
    - intros Hc. eapply H1. constructor. eassumption. do 2 left. eassumption.
  Qed.


  Lemma funname_in_exp_subset_mut :
    (forall e, funname_in_exp e \subset bound_var e) /\
    (forall B, funname_in_fundefs B \subset bound_var_fundefs B).
  Proof.
    exp_defs_induction IHe IHl IHB; intros; normalize_bound_var; simpl; sets.

    eapply Union_Included. eapply Union_Included. now sets.
    eapply Included_trans. eapply name_in_fundefs_bound_var_fundefs. sets.
    sets.
  Qed.

  Lemma funname_in_exp_subset :
    forall e, funname_in_exp e \subset bound_var e.
  Proof. eapply funname_in_exp_subset_mut. Qed.

  Lemma funname_in_fundefs_subset :
    forall e, funname_in_fundefs e \subset bound_var_fundefs e.
  Proof. eapply funname_in_exp_subset_mut. Qed.

  Lemma name_in_fundefs_funname_in_fundefs_Disjoint B1 : 
    unique_bindings_fundefs B1 ->
    Disjoint _ (name_in_fundefs B1) (funname_in_fundefs B1).
  Proof.
    induction B1; intros Hun.
    - inv Hun. simpl. eapply Union_Disjoint_r; eapply Union_Disjoint_l.
      + eapply Disjoint_Included_r. eapply funname_in_exp_subset. sets.
      + eapply Disjoint_sym. eapply Disjoint_Included.
        eapply name_in_fundefs_bound_var_fundefs. eapply funname_in_exp_subset. eassumption. 
      + eapply Disjoint_Included_r. eapply funname_in_fundefs_subset. sets.
      + eauto.
    - sets.
  Qed.
        
  Lemma fun_map_inv_def_funs k S fm rho1 rho2 i sig B1 B2 :
    fun_map_inv k S fm rho1 rho2 i sig ->
    
    preord_env_P_inj cenv PG (name_in_fundefs B1 :|: occurs_free_fundefs B1) i
                     (apply_r (set_list (combine (all_fun_name B1) (all_fun_name B2)) sig))
                     (def_funs B1 B1 rho1 rho1) (def_funs B2 B2 rho2 rho2) ->

    unique_bindings_fundefs B1 ->
    occurs_free_fundefs B1 \subset S ->
    
    Disjoint _ (bound_var_fundefs B1) (Dom_map rho1) ->
    Disjoint _ (bound_var_fundefs B1 \\ funname_in_fundefs B1) (occurs_free_fun_map fm) ->

    Disjoint _ (name_in_fundefs B2) (image (apply_r sig) (occurs_free_fun_map fm)) ->
    
    fun_map_inv k (name_in_fundefs B1 :|: S) (add_fundefs B1 fm) (def_funs B1 B1 rho1 rho1) (def_funs B2 B2 rho2 rho2) i
                (set_list (combine (all_fun_name B1) (all_fun_name B2)) sig).
  Proof.
    revert S fm rho1 rho2 i sig B1 B2. induction k as [k IHk] using lt_wf_rec1.
    intros S fm rho1 rho2 i sig B1 B2 Hf Hrel Hun Hsub Hdis Hdis'' Hdis'.
    intros f ft xs e rhoc B' f' HSin Heq1 Heq2.
    destruct (Decidable_name_in_fundefs B1) as [Dec]. destruct (Dec f).
    - rewrite def_funs_eq in Heq2; eauto. inv Heq2.
      edestruct name_in_fundefs_find_def_is_Some. eassumption. destructAll.
      erewrite add_fundefs_in in Heq1; [| eassumption ]. inv Heq1. split; eauto.
      split; eauto. split; [| split; [| split; [| split ]]].
      + eapply preord_env_P_inj_antimon. eassumption. eapply Setminus_Included_Included_Union.
        eapply Included_trans. eapply occurs_free_in_fun. eapply find_def_correct. eassumption. sets.
      + eapply sub_map_refl.
      + eapply find_def_correct in H. assert (H' := H). eapply unique_bindings_fun_in_fundefs in H; eauto. destructAll.
        eapply Union_Disjoint_r; [| now sets ]. eapply Disjoint_Included; [| | eapply Hdis ]. now sets.
        eapply Included_trans; [| eapply fun_in_fundefs_bound_var_fundefs; eauto ]. now sets.
      + eapply find_def_correct in H. assert (H' := H). eapply unique_bindings_fun_in_fundefs in H; eauto. destructAll.
        eapply Union_Disjoint_r; [| now sets ]. 
        eapply Disjoint_Included; [| | eapply Hdis ]. now sets.
        eapply Included_trans; [| eapply fun_in_fundefs_bound_var_fundefs; eauto ]. now sets.         
      + destruct k; eauto. rewrite <- fun_map_inv_eq. eapply fun_map_inv_antimon. eapply IHk.
        omega. eapply fun_map_inv_mon. eassumption. omega. eassumption. eassumption.
        eassumption. now sets. now sets. now sets. eapply Setminus_Included_Included_Union. 
        eapply Included_trans. eapply occurs_free_in_fun. eapply find_def_correct. eassumption.
        sets.
    - rewrite def_funs_neq in Heq2; eauto.
      rewrite add_fundefs_not_in in Heq1; [| eassumption ]. inv HSin. contradiction.
      edestruct Hf. eassumption. eassumption. eassumption. destructAll. split; eauto. split; eauto.
      split; [| split; [| split; [| split ]]]; eauto.
      + eapply preord_env_P_inj_def_funs_neq_r.
        rewrite apply_r_set_list_f_eq. eapply preord_env_P_inj_extend_lst_not_In_P_r.
        eassumption.
        * rewrite <- Same_set_all_fun_name.
          eapply Disjoint_Included; [| | eapply Hdis'' ]. eapply Included_trans. eapply occurs_free_fun_map_get. eassumption.
          now sets.
          eapply Included_Setminus. eapply name_in_fundefs_funname_in_fundefs_Disjoint. eassumption.
          eapply name_in_fundefs_bound_var_fundefs.
        * rewrite apply_r_set_list_f_eq. eapply Disjoint_Included_l.
          intros x Hc. destruct Hc. destructAll.
          rewrite extend_lst_gso. eapply In_image. eassumption.
          rewrite <- Same_set_all_fun_name. intros Hc. eapply Hdis''. constructor.
          constructor. 
          eapply name_in_fundefs_bound_var_fundefs. eassumption. intros Hc'.
          eapply name_in_fundefs_funname_in_fundefs_Disjoint. eassumption. constructor; eauto.
          eapply occurs_free_fun_map_get. eassumption. eassumption.
          eapply Disjoint_sym. eapply Disjoint_Included; [| | eapply Hdis' ]. eapply image_monotonic.
           eapply occurs_free_fun_map_get. eassumption. reflexivity. 
      + eapply sub_map_trans. eassumption. eapply sub_map_def_funs.
        eapply Disjoint_Included; [| | eapply Hdis ]; sets. eapply name_in_fundefs_bound_var_fundefs. 
      + destruct k; eauto. rewrite <- fun_map_inv_eq in *.
        eapply fun_map_inv_add_fundefs_Disjoint; try eassumption.
        rewrite Union_commut. rewrite Union_assoc. eapply Union_Disjoint_r.
        * eapply Disjoint_Included; [| | eapply Hdis'' ].
          eapply Union_Included. now sets.
          eapply occurs_free_fun_map_get. eassumption.
          eapply Included_Setminus.
          eapply name_in_fundefs_funname_in_fundefs_Disjoint. eassumption. eapply name_in_fundefs_bound_var_fundefs. 
        * eapply Disjoint_Included_r. eapply Dom_map_sub_map. eassumption.
          eapply Disjoint_Included; [| | eapply Hdis ]. sets. eapply name_in_fundefs_bound_var_fundefs. 
  Qed.


  Definition fun_map_vars (fm : fun_map) (F : Ensemble var) (sig : subst) :=
    forall f ft xs e,
      fm ! f = Some (ft, xs, e) ->
      unique_bindings e /\
      NoDup xs /\
      Disjoint _ (bound_var e) (FromList xs :|: occurs_free e) /\
      Disjoint _ (bound_var e \\ funname_in_exp e) (occurs_free_fun_map fm :|: Dom_map fm) /\
      Disjoint _ (FromList xs) (Dom_map fm :|: occurs_free_fun_map fm) /\
      Disjoint _ (funname_in_exp e :|: funfv_in_exp e) (bound_var_fun_map fm) /\

      Disjoint _ F (bound_var e :|: image (apply_r sig) (occurs_free e \\ FromList xs :|: occurs_free_fun_map fm)).

  Lemma fun_map_vars_set fm F sig x v :
    fun_map_vars fm F sig ->
    fun_map_vars fm (F \\ [set v]) (M.set x v sig).
  Proof.
    intros Hfm; intro; intros. eapply Hfm in H. destructAll.
    do 6 (split; eauto). eapply Union_Disjoint_r. now sets.
    eapply Disjoint_Included_r. eapply image_apply_r_set.
    eapply Union_Disjoint_r. now sets. now xsets.
  Qed.

  Lemma apply_r_list_eq xs ys sig :
    NoDup xs ->
    length xs = length ys ->
    apply_r_list (set_list (combine xs ys) sig) xs = ys.
  Proof.
    revert ys sig; induction xs; intros ys sig Hnd Hlen.
    - simpl. destruct ys; eauto. inv Hlen.
    - destruct ys; inv Hlen. inv Hnd.
      simpl. unfold apply_r. rewrite M.gss. f_equal.
      erewrite eq_P_apply_r_list. eapply IHxs. eassumption. eassumption.
      eapply eq_env_P_set_not_in_P_l. eapply eq_env_P_refl. eassumption.
  Qed.

  Lemma NoDup_all_fun_name B :
    unique_bindings_fundefs B ->
    NoDup (all_fun_name B).
  Proof.
    induction B; intros Hc; inv Hc.
    - simpl. constructor; eauto.
      intros Hc. eapply Same_set_all_fun_name in Hc. eapply H5.
      eapply name_in_fundefs_bound_var_fundefs. eassumption.
    - constructor.
  Qed.
    
  Lemma fun_map_vars_def_funs fm S sig B xs :
    fun_map_vars fm S sig ->
    unique_bindings_fundefs B ->

    Disjoint _ (bound_var_fundefs B) (occurs_free_fundefs B) ->
    Disjoint _ (bound_var_fundefs B \\ funname_in_fundefs B \\ name_in_fundefs B) (Dom_map fm :|: occurs_free_fun_map fm) ->
    Disjoint _ (name_in_fundefs B) (bound_var_fun_map fm) ->
    Disjoint _ (occurs_free_fundefs B) (bound_var_fun_map fm) ->
    Disjoint _ (S \\ FromList xs) (bound_var_fundefs B :|: image (apply_r sig) (occurs_free_fundefs B :|: occurs_free_fun_map fm)) ->
    Disjoint _ (funname_in_fundefs B :|: funfv_in_fundefs B) (bound_var_fun_map fm) ->
    
    Datatypes.length (all_fun_name B) = Datatypes.length xs ->
    
    fun_map_vars (add_fundefs B fm) (S \\ FromList xs) (set_list (combine (all_fun_name B) xs) sig).
  Proof.
    intros Hfm Hun Hdis1 Hdis Hdis' Hdis'' Hdis''' Hdis2 Hlen x ft ys e Hget. destruct (Decidable_name_in_fundefs B). destruct (Dec x).
    - edestruct name_in_fundefs_find_def_is_Some; eauto. destructAll. erewrite add_fundefs_in in Hget; eauto.
      inv Hget. edestruct unique_bindings_fun_in_fundefs. eapply find_def_correct. eassumption. eassumption. destructAll.
      assert (Hin1 : bound_var e \subset bound_var_fundefs B).
      { eapply Included_trans; [| eapply fun_in_fundefs_bound_var_fundefs; eapply find_def_correct; eauto ]. now sets. }
      assert (Hin2 : FromList ys \subset bound_var_fundefs B).
      { eapply Included_trans; [| eapply fun_in_fundefs_bound_var_fundefs; eapply find_def_correct; eauto ]. now sets. }
      
      split. eauto. split. eauto. split; [| split; [| split; [| split ]]].
      + eapply Union_Disjoint_r. now sets.
        eapply fun_in_fundefs_Disjoint_bound_Var_occurs_free. eapply find_def_correct. eassumption.
        eassumption. now sets.
      + eapply Union_Disjoint_r.
        * eapply Disjoint_Included_r. eapply occurs_free_fun_map_add_fundefs.
          eapply Union_Disjoint_r. eapply Union_Disjoint_r. 
          eapply Disjoint_Included; [| | eapply Hdis1 ]; now sets. now sets.
          eapply Disjoint_Included; [| | eapply Hdis ]. now sets.
          eapply Included_Setminus. now sets. 
          eapply fun_in_fundefs_bound_var_Setminus. eapply find_def_correct. eassumption. eassumption.
        * rewrite Dom_map_add_fundefs. eapply Union_Disjoint_r. now sets.
          eapply Disjoint_Included; [| | eapply Hdis ]. now sets.
          eapply Included_Setminus. now sets. 
          eapply fun_in_fundefs_bound_var_Setminus. eapply find_def_correct. eassumption. eassumption.
      + eapply Union_Disjoint_r.
        * rewrite Dom_map_add_fundefs. eapply Union_Disjoint_r. eassumption.
          eapply Disjoint_Included_l.
          eapply Included_Setminus. eassumption. 
          eapply fun_in_fundefs_FromList_subset. eapply find_def_correct. eassumption. eassumption.
          now sets.
        * eapply Disjoint_Included_r. eapply occurs_free_fun_map_add_fundefs.
          eapply Union_Disjoint_r. eapply Union_Disjoint_r.
          eapply Disjoint_Included_l. eassumption. sets.
          eassumption.
          eapply Disjoint_Included_l. eapply Included_Setminus. eassumption. 
          eapply fun_in_fundefs_FromList_subset. eapply find_def_correct. eassumption. eassumption.
          sets.
      + eapply Disjoint_Included_r. eapply bound_var_fun_map_add_fundefs_un. eassumption.
        eapply Union_Disjoint_r.
        * eapply Disjoint_Included_l. admit. admit.
          (* eapply fun_in_fundefs_bound_var_Setminus. *)
          (* (* now sets. admit. *)           *)
        * eapply Disjoint_Included; [| | eapply Hdis2 ]. now sets. admit.
      (* eapply fun_in_fundefs_bound_var_Setminus. funname_in_fundefs_subset.  *)
      + eapply Union_Disjoint_r. now sets. eapply Disjoint_Included_r.
        eapply image_apply_r_set_list. now eauto. eapply Union_Disjoint_r. now sets.
        rewrite <- Same_set_all_fun_name. rewrite Setminus_Union_distr.
        eapply Disjoint_Included_r. eapply image_monotonic. eapply Included_Union_compat. reflexivity.
        eapply Included_Setminus_compat. eapply occurs_free_fun_map_add_fundefs. reflexivity.
        rewrite !Setminus_Union_distr. rewrite Setminus_Same_set_Empty_set. repeat normalize_sets.
        rewrite image_Union. eapply Union_Disjoint_r; [| now xsets ].
        eapply Disjoint_Included_r. eapply image_monotonic.
        eapply Included_Setminus_compat. eapply Included_Setminus_compat.
        eapply occurs_free_in_fun. eapply find_def_correct. eassumption. reflexivity. reflexivity.
        rewrite !Setminus_Union_distr. rewrite Setminus_Same_set_Empty_set.
        rewrite Setminus_Union. rewrite (Setminus_Included_Empty_set (name_in_fundefs _)); [| now sets ].
        repeat normalize_sets. xsets.
    - rewrite add_fundefs_not_in in Hget; eauto. edestruct Hfm. eassumption. destructAll.
      split; eauto. split; eauto. split; [| split; [| split; [| split ]]].
      + now sets.        
      + rewrite Dom_map_add_fundefs. eapply Union_Disjoint_r.
        * eapply Disjoint_Included_r. eapply occurs_free_fun_map_add_fundefs. eapply Union_Disjoint_r; [| now sets ].
          eapply Union_Disjoint_r.
          eapply Disjoint_sym. eapply Disjoint_Included_r; [| eassumption ].
          eapply Included_trans; [| eapply bound_var_fun_map_get; eauto ]. now sets.
          eapply Disjoint_sym. eapply Disjoint_Included_r; [| eassumption ].
          eapply Included_trans; [| eapply bound_var_fun_map_get; eauto ]. now sets.
        * eapply Union_Disjoint_r. sets.
          eapply Disjoint_sym. eapply Disjoint_Included_r; [| eassumption ].
          eapply Included_trans; [| eapply bound_var_fun_map_get; eauto ]. now sets.
          now sets.
      + rewrite Dom_map_add_fundefs. eapply Union_Disjoint_r. eapply Union_Disjoint_r.
        eapply Disjoint_sym. eapply Disjoint_Included_r; [| eassumption ].
        eapply Included_trans; [| eapply bound_var_fun_map_get; eauto ]. now sets.
        now sets.
        eapply Disjoint_Included_r. eapply occurs_free_fun_map_add_fundefs. 
        eapply Union_Disjoint_r; [| now sets ]. eapply Union_Disjoint_r.
        eapply Disjoint_sym. eapply Disjoint_Included_r; [| eassumption ].
        eapply Included_trans; [| eapply bound_var_fun_map_get; eauto ]. now sets.
        eapply Disjoint_sym. eapply Disjoint_Included_r; [| eassumption ].
        eapply Included_trans; [| eapply bound_var_fun_map_get; eauto ]. now sets.
      + eapply Disjoint_Included_r. eapply bound_var_fun_map_add_fundefs_un. eassumption.
        eapply Union_Disjoint_r; [| eassumption ]. admit.
      + eapply Union_Disjoint_r. now sets. 
        eapply Disjoint_Included_r. eapply image_apply_r_set_list. eassumption.
        eapply Union_Disjoint_r. now sets. eapply Disjoint_Included_r.
        rewrite <- Same_set_all_fun_name. rewrite Setminus_Union_distr. eapply image_monotonic.
        eapply Included_Union_compat. reflexivity. eapply Included_Setminus_compat.
        eapply occurs_free_fun_map_add_fundefs. reflexivity.
        rewrite !Setminus_Union_distr. rewrite Setminus_Same_set_Empty_set. repeat normalize_sets.
        rewrite !image_Union in *. eapply Union_Disjoint_r. now xsets. eapply Union_Disjoint_r; [| now xsets ]. 
        xsets.
  Qed.
  
  Opaque preord_exp'.
  
  Lemma inline_correct_mut d : 
    (forall e sig fm st S
            (Hun : unique_bindings e)
            (Hdis1 : Disjoint _ (bound_var e) (occurs_free e))
            (Hdis2 : Disjoint _ S (bound_var e :|: image (apply_r sig) (occurs_free e :|: occurs_free_fun_map fm)))
            (Hdis3 : Disjoint _ (bound_var e \\ funname_in_exp e) (Dom_map fm :|: occurs_free_fun_map fm))
            (Hdis4 : Disjoint _ (funname_in_exp e :|: funfv_in_exp e) (bound_var_fun_map fm))
            
            (Hfm : fun_map_vars fm S sig),
        {{ fun _ s => fresh S (next_var (fst s)) }}
          beta_contract St IH d e sig fm st
        {{ fun _ s e' s' =>
             fresh S (next_var (fst s')) /\ next_var (fst s) <= next_var (fst s') /\
             unique_bindings e' /\
             occurs_free e' \subset image (apply_r sig) (occurs_free e :|: occurs_free_fun_map fm) /\
             bound_var e' \subset (Range (next_var (fst s)) (next_var (fst s')))  /\
             (forall k rho1 rho2,
                 preord_env_P_inj cenv PG (occurs_free e) k (apply_r sig) rho1 rho2 ->
                 Disjoint _ (bound_var e) (Dom_map rho1) ->
                 fun_map_inv d (occurs_free e) fm rho1 rho2 k sig ->
                 preord_exp cenv P1 PG k (e, rho1) (e', rho2)) }} ) /\ 

    (forall B sig sig0 fm st S
            (Hun : unique_bindings_fundefs B)
            (Hdis1 : Disjoint _ (bound_var_fundefs B) (occurs_free_fundefs B))
            (Hdis2 : Disjoint _ S (bound_var_fundefs B :|: image (apply_r sig) (occurs_free_fundefs B :|: occurs_free_fun_map fm)))
            (Hdis3 : Disjoint _ (bound_var_fundefs B \\ name_in_fundefs B \\ funname_in_fundefs B) (Dom_map fm :|: occurs_free_fun_map fm))
            (Hdis4 : Disjoint _ (funname_in_fundefs B :|: funfv_in_fundefs B) (bound_var_fun_map fm))
            
            (Hfm : fun_map_vars fm S sig), 
        {{ fun _ s => fresh S (next_var (fst s)) }}
          beta_contract_fundefs St IH d sig0 sig fm B st
        {{ fun _ s B' s' =>
             fresh S (next_var (fst s')) /\ next_var (fst s) <= next_var (fst s') /\
             unique_bindings_fundefs B' /\
             occurs_free_fundefs B' \subset image (apply_r sig) (occurs_free_fundefs B :|: occurs_free_fun_map fm) /\
             bound_var_fundefs B' \subset (Range (next_var (fst s)) (next_var (fst s'))) /\
             all_fun_name B' = apply_r_list sig (all_fun_name B) /\
             (forall f xs ft e1,
                 find_def f B = Some (ft, xs, e1) ->
                 exists xs' e2,
                   find_def (apply_r sig f) B' = Some (ft, xs', e2) /\
                   length xs = length xs' /\ NoDup xs' /\ FromList xs' \subset S /\
                   (forall rho1 rho2 k,
                       preord_env_P_inj cenv PG (occurs_free_fundefs B) k (apply_r sig <{ xs ~> xs' }>) rho1 rho2 ->
                       Disjoint _ (bound_var e1) (Dom_map rho1) ->
                       fun_map_inv d (occurs_free_fundefs B) fm rho1 rho2 k sig ->
                       preord_exp cenv P1 PG k (e1, rho1) (e2, rho2))) }}).

  Proof.
    induction d as [d IHd] using lt_wf_rec1.
    exp_defs_induction IHe IHl IHB; intros; inv Hun; try rewrite beta_contract_eq.
    - (* constr *)
      eapply bind_triple. eapply pre_transfer_r. now eapply get_name_fresh. 
      intros x w1. simpl. eapply pre_curry_l. intros Hf. 
      eapply bind_triple. eapply frame_rule. eapply frame_rule. eapply IHe with (S := S \\ [set x]).
      + eassumption.
      + repeat normalize_bound_var_in_ctx. repeat normalize_occurs_free_in_ctx.
        eapply Disjoint_Included_r. eapply Included_Union_Setminus with (s2 := [set v]). tci.
        eapply Union_Disjoint_r. eapply Disjoint_Included; [| | eapply Hdis1 ]; sets.
        eapply Disjoint_Singleton_r. eassumption.
      + eapply Disjoint_Included_r.
        eapply Included_Union_compat. reflexivity.
        eapply image_apply_r_set. 
        repeat normalize_bound_var_in_ctx. repeat normalize_occurs_free_in_ctx.
        eapply Union_Disjoint_r. now sets.
        eapply Union_Disjoint_r. now sets.
        eapply Disjoint_Included; [| | eapply Hdis2 ].
        rewrite Setminus_Union_distr. rewrite !image_Union. now xsets. now sets.
      + eapply Disjoint_Included_l; [| eassumption ]. normalize_bound_var. sets.
      + eassumption.
      + eapply fun_map_vars_set. eassumption.
      + intros e' w2. eapply return_triple.
        intros _ st'. intros [Hf1 [Hf2 [Hf3 [Hf4 [Hun [Hsub [Hsub' Hsem]]]]]]].
        split; [| split; [| split; [| split; [| split ]]]].
        * eapply fresh_monotonic;[| eassumption ]. sets.
        * zify; omega.
        * constructor; [| eassumption ].
          intros Hc. eapply Hsub' in Hc. eapply Disjoint_Range; [| constructor; [ eapply Hf1 | eapply Hc ]].
          reflexivity.
        * repeat normalize_occurs_free. rewrite !image_Union.
          rewrite <- FromList_apply_list. rewrite <- !Union_assoc. eapply Included_Union_compat. reflexivity. 
          eapply Included_trans. eapply Included_Setminus_compat.
          eapply Included_trans. eassumption. now eapply image_apply_r_set. reflexivity.
          rewrite !Setminus_Union_distr. rewrite Setminus_Same_set_Empty_set. normalize_sets.
          rewrite image_Union. sets.
        * normalize_bound_var. eapply Union_Included. eapply Included_trans. eassumption.
          eapply Range_Subset. zify; omega. reflexivity.
          eapply Included_trans. eapply Singleton_Included. eassumption. eapply Range_Subset. reflexivity.
          zify; omega.
        * intros r1 r2 k Henv Hdis Hfm'. eapply preord_exp_const_compat.
          eassumption. eassumption.
          eapply Forall2_preord_var_env_map. eassumption. normalize_occurs_free. now sets.          
          intros. eapply Hsem. 
          rewrite apply_r_set_f_eq. eapply preord_env_P_inj_set_alt.
          -- eapply preord_env_P_inj_antimon. eapply preord_env_P_inj_monotonic; [| eassumption ].
             omega. normalize_occurs_free. sets.
          -- rewrite preord_val_eq. split. reflexivity.
             eapply Forall2_Forall2_asym_included. eassumption.
          -- intros Hc. eapply Hdis2. constructor. eapply Hf. eapply Hf1. 
             right. normalize_occurs_free. rewrite !image_Union. left. right. eassumption.
          -- repeat normalize_bound_var_in_ctx. rewrite Dom_map_set.
             eapply Union_Disjoint_r.
             ++ eapply Disjoint_Singleton_r. eassumption.
               (* eapply Disjoint_Included_r. eapply occurs_free_in_env_set. simpl. normalize_sets. *)
               (*  eapply Disjoint_Included; [| | eapply Hdis]; sets. *)
             ++ sets.
                (* eapply Union_Disjoint_r. *)
                (* ** eapply Disjoint_Singleton_r. eassumption. *)
                (* ** eapply Disjoint_Included; [| | eapply Hdis]; sets. *)
            (* eapply Disjoint_Included_r. *)
            (*  eapply Included_trans. eapply image_monotonic. eapply occurs_free_in_env_set. simpl. repeat normalize_sets. *)
            (*  now eapply image_apply_r_set. *)
            (*  eapply Union_Disjoint_r. now sets. sets.  *)
          -- eapply fun_map_inv_antimon. eapply fun_map_inv_set. eapply fun_map_inv_i_mon. eassumption. omega.
             intros Hc. inv Hc. inv H2.
             ++ eapply Hdis. normalize_bound_var. constructor. now right. eassumption.
             ++ eapply Hdis3. constructor. normalize_bound_var. simpl. constructor. now right.
                (* now right. now right; eauto. *) admit.
                now left; eauto.
             ++ eapply Hdis3. normalize_bound_var. constructor. constructor. now right. simpl. admit.
                now right; eauto.
             ++ intros Hc. eapply Hdis2. constructor; try eassumption.
                eapply fresh_Range; [| eassumption ]. eassumption. rewrite image_Union. eauto.
             ++ normalize_occurs_free. rewrite !Union_assoc. rewrite Union_Setminus_Included; sets; tci.
    - (* Ecase [] *)
      admit.
    - (* Ecase (_ :: _) *)
      admit.
    - (* Eproj *)
      admit.
    - (* Eletapp *)
      admit. 
    - (* Efun *) 
      simpl. destruct (update_funDef St IH f2 sig st). 
      eapply bind_triple. eapply pre_transfer_r. now eapply get_names_lst_fresh. intros xs w. simpl.
      eapply pre_curry_l. intros Hf. eapply pre_curry_l. intros Hnd.  eapply pre_curry_l. intros Hlen.
      
      assert (Hfm' : fun_map_vars (add_fundefs f2 fm) (S \\ FromList xs) (set_list (combine (all_fun_name f2) xs) sig)).
      { eapply fun_map_vars_def_funs; (try now eauto).
        + repeat normalize_bound_var_in_ctx. repeat normalize_occurs_free_in_ctx.
          eapply Disjoint_Included; [| | eapply Hdis1 ]; sets.
        + eapply Disjoint_Included_l; [| eapply Hdis3 ]. simpl. admit.
        + sets.
        + eapply Disjoint_Included_l; [| eassumption ]. simpl. sets.
        + repeat normalize_bound_var_in_ctx. repeat normalize_occurs_free_in_ctx.
          eapply Disjoint_Included; [| | eapply Hdis2 ]; sets. }      
      
      eapply bind_triple. 
      { do 2 eapply frame_rule. eapply IHB with (S := S \\ FromList xs).
        - eassumption.
        - repeat normalize_occurs_free_in_ctx. repeat normalize_bound_var_in_ctx.
          eapply Disjoint_Included; [| | eapply Hdis1 ]; try now sets.
        - repeat normalize_occurs_free_in_ctx. repeat normalize_bound_var_in_ctx. 
          rewrite image_Union in Hdis2. eapply Union_Disjoint_r. now sets.
          eapply Disjoint_Included_r. eapply image_apply_r_set_list. now eauto.
          eapply Union_Disjoint_r. now sets.
          rewrite <- Same_set_all_fun_name. rewrite Setminus_Union_distr. rewrite image_Union. eapply Union_Disjoint_r.
          now xsets.
          eapply Disjoint_Included_r. eapply image_monotonic. eapply Included_Setminus_compat. eapply occurs_free_fun_map_add_fundefs. reflexivity.
          rewrite !Setminus_Union_distr. rewrite Setminus_Same_set_Empty_set. repeat normalize_sets. rewrite image_Union. xsets.
        - repeat normalize_occurs_free_in_ctx. repeat normalize_bound_var_in_ctx.
          rewrite Dom_map_add_fundefs. eapply Union_Disjoint_r.
          + eapply Union_Disjoint_r. now sets.
            eapply Disjoint_Included; [| | eapply Hdis3 ]. now sets. admit.            
          + eapply Disjoint_Included_r. eapply occurs_free_fun_map_add_fundefs. eapply Union_Disjoint_r.
            eapply Union_Disjoint_r. eapply Disjoint_Included; [| | eapply Hdis1 ]. now sets. now sets.
            now sets.
            eapply Disjoint_Included; [| | eapply Hdis3 ]. now sets. admit.
        - eapply Disjoint_Included_r. eapply bound_var_fun_map_add_fundefs_un. eassumption. eapply Union_Disjoint_r.
          + eapply Union_Disjoint_l. now sets. admit. (* ?? *)
          + eapply Disjoint_Included_l; [| eassumption ]. sets.
        - eassumption. }

      intros fds' w'. simpl.
      eapply pre_curry_l. intros Hsub. eapply pre_curry_l. intros Hr. 
      eapply bind_triple.
      { eapply pre_strenghtening.
        2:{ eapply frame_rule. eapply IHe with (S := S \\ FromList xs).
            + eassumption.
            + repeat normalize_bound_var_in_ctx. repeat normalize_occurs_free_in_ctx.
              * eapply Disjoint_Included_r. eapply Included_Union_Setminus with (s2 := name_in_fundefs f2). now tci.
                eapply Union_Disjoint_r. eapply Disjoint_Included; [| | eapply Hdis1 ]; now sets.
                eapply Disjoint_Included_r. eapply name_in_fundefs_bound_var_fundefs. now sets.
            + repeat normalize_bound_var_in_ctx. repeat normalize_occurs_free_in_ctx.
              eapply Union_Disjoint_r. now sets. eapply Disjoint_Included_r.
              eapply image_apply_r_set_list. now eauto.
              rewrite image_Union in Hdis2. eapply Union_Disjoint_r. now xsets.
              rewrite <- Same_set_all_fun_name. rewrite Setminus_Union_distr. rewrite image_Union.
              eapply Union_Disjoint_r. now xsets.
              eapply Disjoint_Included_r. eapply image_monotonic. eapply Included_Setminus_compat. eapply occurs_free_fun_map_add_fundefs. reflexivity.
              rewrite !Setminus_Union_distr. rewrite image_Union. xsets.
            + repeat normalize_bound_var_in_ctx. repeat normalize_occurs_free_in_ctx.
              rewrite Dom_map_add_fundefs. eapply Union_Disjoint_r.
              * eapply Union_Disjoint_r.
                -- eapply Disjoint_Included_r. eapply name_in_fundefs_bound_var_fundefs. now sets.
                -- eapply Disjoint_Included; [| | eapply Hdis3 ]; sets. simpl. admit.
              * eapply Disjoint_Included_r. eapply occurs_free_fun_map_add_fundefs.
                eapply Union_Disjoint_r. eapply Union_Disjoint_r. 
                -- eapply Disjoint_Included; [| | eapply Hdis1 ]; sets.
                -- eapply Disjoint_Included_r. eapply name_in_fundefs_bound_var_fundefs. now sets.
                -- eapply Disjoint_Included; [| | eapply Hdis3 ]. now sets.
                   simpl. admit.
            + eapply Disjoint_Included_r. eapply bound_var_fun_map_add_fundefs_un. eassumption. eapply Union_Disjoint_r.
              * admit. (* ?? *)
              * eapply Disjoint_Included; [| | eapply Hdis4 ]. reflexivity. simpl. admit. 
            + eassumption. }
        
      simpl. intros u w1 [Hyp Hyp']. split. eapply Hyp'. eassumption. }
      intros e' w''. eapply return_triple. intros _ w''' Hyp. destructAll.
      assert (Hnd' := NoDup_all_fun_name _ H2).
      split; [| split; [| split; [| split; [| split ]]]].
      * eapply fresh_monotonic; [| eassumption ]. sets.
      * zify; omega. 
      * constructor. eassumption. eassumption.
        eapply Disjoint_Included. eassumption. eassumption.
        eapply Disjoint_sym. eapply Disjoint_Range. reflexivity.
      * repeat normalize_occurs_free. eapply Union_Included.
        -- eapply Included_trans. eapply Included_Setminus. eapply Disjoint_sym.
           eapply occurs_free_fundefs_name_in_fundefs_Disjoint. reflexivity.
           eapply Setminus_Included_Included_Union. eapply Included_trans. eassumption.
           eapply Included_trans. eapply image_apply_r_set_list. now eauto.
           rewrite (Same_set_all_fun_name fds'). rewrite H12.
           rewrite apply_r_list_eq; eauto. eapply Union_Included. now sets.
           eapply Included_Union_preserv_l. rewrite <- Same_set_all_fun_name.
           rewrite Setminus_Union_distr. rewrite !image_Union. eapply Union_Included. now sets.
           eapply Included_trans. eapply image_monotonic. eapply Included_Setminus_compat.
           eapply occurs_free_fun_map_add_fundefs. reflexivity.
           rewrite !Setminus_Union_distr, Setminus_Same_set_Empty_set. repeat normalize_sets.
           rewrite image_Union. now xsets.
        -- eapply Included_trans. eapply Included_Setminus_compat. eassumption. reflexivity.
           eapply Setminus_Included_Included_Union. 
           eapply Included_trans. eapply image_apply_r_set_list. now eauto.
           rewrite (Same_set_all_fun_name fds'). rewrite H12.
           rewrite apply_r_list_eq; eauto. eapply Union_Included. now sets.
           eapply Included_Union_preserv_l. rewrite <- Same_set_all_fun_name.
           rewrite Setminus_Union_distr. rewrite !image_Union. eapply Union_Included. now sets.
           eapply Included_trans. eapply image_monotonic. eapply Included_Setminus_compat.
           eapply occurs_free_fun_map_add_fundefs. reflexivity.
           rewrite !Setminus_Union_distr, Setminus_Same_set_Empty_set. repeat normalize_sets.
           rewrite image_Union. now xsets.
      * normalize_bound_var. eapply Union_Included.
        -- eapply Included_trans. eassumption. eapply Range_Subset. eassumption. zify; omega.
        -- eapply Included_trans. eassumption. eapply Range_Subset. zify; omega. reflexivity.
      * intros k rho1 rho2 Henv Hdis Hfm''. eapply preord_exp_fun_compat.
        eassumption. eassumption.
        assert (Hseq :  apply_r_list (set_list (combine (all_fun_name f2) xs) sig) (all_fun_name f2) = xs).
        { rewrite apply_r_list_eq. reflexivity. now eauto. now eauto. }
        assert (Hrel : preord_env_P_inj cenv PG
                                        (name_in_fundefs f2 :|: occurs_free (Efun f2 e)) 
                                        (k - 1) (apply_r (set_list (combine (all_fun_name f2) xs) sig))
                                        (def_funs f2 f2 rho1 rho1) (def_funs fds' fds' rho2 rho2)).
        { assert (Hi : (k - 1 <= k)%nat) by omega. 
          revert Hi. generalize (k - 1)%nat as i. intros i Hi. induction i as [i IHi] using lt_wf_rec1. 
          intros x HIn v Hgetx. destruct (Decidable_name_in_fundefs f2). destruct (Dec x).
          - rewrite def_funs_eq in Hgetx; [| now eauto ]. inv Hgetx. eexists. split.
            + rewrite def_funs_eq. reflexivity. eapply Same_set_all_fun_name. 
              rewrite H12. rewrite FromList_apply_list. eapply In_image.
              rewrite <- Same_set_all_fun_name. eassumption.
            + rewrite preord_val_eq. intros vs1 vs2 j t1 ys1 e2 rho1' Hlen' Hfind Hset.
              edestruct H13. eassumption. destructAll.
              edestruct set_lists_length2 with (xs2 := x0) (vs2 := vs2) (rho' := def_funs fds' fds' rho2 rho2). 
              now eauto. eassumption. now eauto. do 3 eexists. split. eassumption. split. now eauto. 
              intros Hlt Hvs. eapply preord_exp_post_monotonic. eassumption. eapply H18.
              * eapply preord_env_P_inj_set_lists_alt; [| eassumption | | | | | now eauto | now eauto ]. 
                -- eapply preord_env_P_inj_antimon. eapply IHi. eassumption. omega.
                   normalize_occurs_free. sets.
                -- eapply unique_bindings_fun_in_fundefs. eapply find_def_correct. eassumption.
                   eassumption.
                -- eassumption.
                -- eassumption.
                -- eapply Disjoint_Included_r. eassumption.
                   eapply Disjoint_Included_l. eapply image_apply_r_set_list. now eauto.
                   eapply Union_Disjoint_l. now sets. rewrite <- Same_set_all_fun_name.
                   eapply Disjoint_sym. eapply Disjoint_Included; [| | eapply Hdis2 ].
                   normalize_occurs_free. now xsets. now sets.
              * rewrite Dom_map_set_lists; [| now eauto ]. rewrite Dom_map_def_funs.
                eapply Union_Disjoint_r. eapply unique_bindings_fun_in_fundefs. eapply find_def_correct. eassumption. eassumption.
                eapply Union_Disjoint_r. eapply unique_bindings_fun_in_fundefs. eapply find_def_correct. eassumption. eassumption.
                eapply Disjoint_Included_l; [| eapply Hdis ]. normalize_bound_var. eapply Included_Union_preserv_l.
                eapply Included_trans; [| eapply fun_in_fundefs_bound_var_fundefs ]; [| eapply find_def_correct; eassumption ]. sets.
              * eapply fun_map_inv_antimon. eapply fun_map_inv_set_lists; [ | | | now eauto ].
                eapply fun_map_inv_set_lists_r; [| | now eauto ]. 
                -- rewrite <- Hseq. rewrite <- H12. eapply fun_map_inv_def_funs.
                   eapply fun_map_inv_i_mon. eassumption. omega. eapply preord_env_P_inj_antimon.
                   rewrite H12. rewrite Hseq. eapply IHi. eassumption. omega. normalize_occurs_free. sets.
                   eassumption. normalize_occurs_free. now sets.
                   repeat normalize_bound_var_in_ctx. now sets.
                   eapply Disjoint_Included; [ | | eapply Hdis3 ]. now sets. simpl. admit.
                   eapply Disjoint_Included_l. eapply Included_trans. eapply name_in_fundefs_bound_var_fundefs. eassumption.
                   eapply Disjoint_Included; [| | eapply Hdis2 ]. rewrite image_Union. now sets.
                   intros z Hin. eapply Hf. unfold Ensembles.In, Range in *. zify. omega.
                -- eapply Disjoint_Included_l. eassumption. eapply Disjoint_Included_r.
                   eapply image_apply_r_set_list. now eauto. eapply Union_Disjoint_r. now sets.
                   eapply Disjoint_Included; [| | eapply Hdis2 ]. rewrite <- Same_set_all_fun_name.
                   eapply Included_trans. eapply image_monotonic. eapply Included_Setminus_compat.
                   eapply occurs_free_fun_map_add_fundefs. reflexivity. rewrite !Setminus_Union_distr.
                   rewrite Setminus_Same_set_Empty_set. repeat normalize_sets. 
                   normalize_occurs_free. rewrite !image_Union. now xsets. now sets.
                -- eapply unique_bindings_fun_in_fundefs. eapply find_def_correct. eassumption. eassumption.
                -- eapply Disjoint_Included_r. eapply Included_Union_compat.
                   eapply Dom_map_def_funs. eapply Dom_map_add_fundefs.
                   edestruct unique_bindings_fun_in_fundefs. eapply find_def_correct. eapply Hfind. eassumption. destructAll. 
                   eapply Union_Disjoint_r. eapply Union_Disjoint_r. now sets. 
                   eapply Disjoint_Included_l; [| eassumption ]. normalize_bound_var. eapply Included_Union_preserv_l. 
                   eapply Included_trans; [| eapply fun_in_fundefs_bound_var_fundefs; eapply find_def_correct; eapply Hfind ]. now sets.                   
                   eapply Union_Disjoint_r. now sets.
                   eapply Disjoint_Included; [| | eapply Hdis3 ]. now sets.
                   eapply Included_trans. eapply fun_in_fundefs_FromList_subset. eapply find_def_correct. eassumption. eassumption.
                   admit. 
                   (* simpl. rewrite <-Setminus_Union.  *)
                   (* eapply Included_trans. eapply fun_in_fundefs_FromList_subset. eapply find_def_correct. eassumption. eassumption. *)
                   (* simpl. normalize_bound_var. *)
                   (* eapply Disjoint_Included_l. eapply Included_trans; [| eapply fun_in_fundefs_bound_var_fundefs; eapply find_def_correct; eapply Hfind ]. *)
                   (* now sets. eapply Disjoint_Included; [| | eapply Hdis3 ]. now sets. normalize_bound_var. now sets. *)
                -- normalize_occurs_free. sets.
          - inv HIn. contradiction. rewrite def_funs_neq in Hgetx; [| eassumption ]. eapply Henv in Hgetx; [| eassumption ]. destructAll. 
            eexists. rewrite apply_r_set_list_f_eq. rewrite extend_lst_gso. rewrite def_funs_neq. 
            split; eauto. eapply preord_val_monotonic. eassumption. omega. 
            + intros Hc. eapply Same_set_all_fun_name in Hc. rewrite H12 in Hc.
              rewrite apply_r_list_eq in Hc; [| | now eauto ]. eapply Hdis2. constructor. 
              2:{ right. eapply In_image. now left; eauto. } 
              eapply fresh_Range. 2:{ eapply Hsub. eassumption. } eassumption. eassumption.
            + rewrite <- Same_set_all_fun_name. intros Hc. eapply Hdis1. constructor. normalize_bound_var. left.
              now eapply name_in_fundefs_bound_var_fundefs. now eauto. }
        eapply H8.
        -- eapply preord_env_P_inj_antimon. eassumption. normalize_occurs_free.
           rewrite !Union_assoc. rewrite Union_Setminus_Included; sets. tci.
        -- repeat normalize_bound_var_in_ctx.
           rewrite Dom_map_def_funs. eapply Union_Disjoint_r.
           ++ eapply Disjoint_Included_r. eapply name_in_fundefs_bound_var_fundefs. sets.
           ++ sets.
        -- eapply fun_map_inv_antimon. rewrite <- Hseq. rewrite <- H12. eapply fun_map_inv_def_funs.
           eapply fun_map_inv_i_mon. eassumption. omega. rewrite H12, Hseq. eapply preord_env_P_inj_antimon.
           eassumption. normalize_occurs_free. now sets. eassumption. normalize_occurs_free. sets.
           repeat normalize_bound_var_in_ctx. now sets. 
           
           eapply Disjoint_Included; [ | | eapply Hdis3 ]. now sets. admit.
           eapply Disjoint_Included_l. eapply Included_trans. eapply name_in_fundefs_bound_var_fundefs. eassumption.
           eapply Disjoint_Included; [| | eapply Hdis2 ]. rewrite image_Union. now sets.
           intros z Hin. eapply Hf. unfold Ensembles.In, Range in *. zify. omega.
           normalize_occurs_free. rewrite !Union_assoc. rewrite Union_Setminus_Included. now sets. tci. now sets.
    - (* Eapp *)
      simpl. destruct (update_App St IH (apply_r sig v) t (apply_r_list sig l) st) as [s b] eqn:Hup. 
      + destruct b.
        * destruct (fm ! v) as [[[ft xs] e] |] eqn:Heqf.
          destruct d.
          -- eapply return_triple.
             intros. split; [| split; [| split; [| split; [| split ]]]]; try eassumption.
             ++ reflexivity.
             ++ constructor. 
             ++ repeat normalize_occurs_free. rewrite !image_Union, image_Singleton.
                rewrite FromList_apply_list. sets.
             ++ normalize_bound_var. sets.
             ++ intros. eapply preord_exp_app_compat.
                assumption. assumption.
                eapply H0. now constructor.
                eapply Forall2_preord_var_env_map. eassumption.
                now constructor.              
          -- destruct (Datatypes.length xs =? Datatypes.length l)%nat eqn:Hbeq.
             { symmetry in Hbeq. eapply beq_nat_eq in Hbeq.      
               edestruct Hfm. eassumption. destructAll. eapply post_weakening; [| eapply IHd ].
               ++ simpl. intros. destructAll. 
                  split; [| split; [| split; [| split; [| split ]]]]; try eassumption.
                  ** eapply Included_trans. eassumption. 
                     eapply Included_trans. eapply image_apply_r_set_list.
                     unfold apply_r_list. rewrite list_length_map. eassumption.
                     normalize_occurs_free. rewrite !image_Union. rewrite FromList_apply_list.
                     eapply Union_Included. now sets.
                     rewrite !Setminus_Union_distr. rewrite !image_Union. eapply Included_Union_preserv_r.
                     eapply Union_Included; [| now sets ].
                     eapply image_monotonic. intros z Hin. do 4 eexists; split; eauto.
                  ** intros. eapply preord_exp_app_l.
                     --- admit. (* post *)
                     --- admit. (* post *) 
                     --- intros. assert (Hf := H14). assert (Heqf' := Heqf). edestruct H14; eauto. destructAll.
                         do 2 subst_exp. eapply H11.
                         +++ edestruct preord_env_P_inj_get_list_l. now eapply H12. normalize_occurs_free. now sets.
                             eassumption. destructAll.                           
                             eapply preord_env_P_inj_set_lists_l'; try eassumption.
                         +++ erewrite Dom_map_set_lists; [| eassumption ]. rewrite Dom_map_def_funs. xsets.
                             eapply Union_Disjoint_r; xsets. eapply Disjoint_Included_r; [| eapply H1 ]. sets.
                         +++ eapply fun_map_inv_antimon. eapply fun_map_inv_set_lists; [ | | | eassumption ].
                             *** eapply fun_map_inv_sig_extend_Disjoint. rewrite <- fun_map_inv_eq in *. eapply H25.
                                 eapply Disjoint_Included_r; [| eapply H3 ]. sets.
                             *** eassumption.
                             *** rewrite Dom_map_def_funs. eapply Union_Disjoint_r. now sets. 
                                 clear H24. xsets.
                             *** rewrite Union_Setminus_Included. sets. tci. sets.
               ++ omega.
               ++ eassumption.
               ++ xsets.
               ++ eapply Union_Disjoint_r. now sets.
                  eapply Disjoint_Included_r. eapply image_apply_r_set_list.
                  unfold apply_r_list. rewrite list_length_map. eassumption.
                  eapply Union_Disjoint_r.
                  eapply Disjoint_Included_r; [| eapply Hdis2 ]. normalize_occurs_free.
                  rewrite image_Union. rewrite FromList_apply_list. now sets.
                  rewrite Setminus_Union_distr. now xsets.
               ++ sets.
               ++ s
               ++ (* Make lemma if needed about fun_map_vars fm S (set_list (combine xs (apply_r_list sig l)) sig) *)
                  intros ? ? ? ? ?. edestruct Hfm; eauto. destructAll.
                  repeat (split; [ now eauto |]). eapply Union_Disjoint_r. now sets.
                  eapply Disjoint_Included_r. eapply image_apply_r_set_list.
                  unfold apply_r_list. rewrite list_length_map. eassumption.
                  eapply Union_Disjoint_r.
                  eapply Disjoint_Included_r; [| eapply Hdis2 ]. normalize_occurs_free.
                  rewrite image_Union. rewrite FromList_apply_list. now sets. now sets. }
             { eapply return_triple. 
               intros. split; [| split; [| split; [| split; [| split ]]]]; try eassumption.
               ++ reflexivity.
               ++ constructor.
               ++ simpl. repeat normalize_occurs_free. rewrite !image_Union, image_Singleton.
                  rewrite FromList_apply_list. sets.
               ++ normalize_bound_var. sets.
               ++ intros. eapply preord_exp_app_compat.
                  assumption. assumption.
                  eapply H0. now constructor.
                  eapply Forall2_preord_var_env_map. eassumption.
                  now constructor. }
          -- eapply return_triple.
             intros. split; [| split; [| split; [| split; [| split ]]]]; try eassumption.
             ++ reflexivity.
             ++ constructor.
             ++ simpl. repeat normalize_occurs_free. rewrite !image_Union, image_Singleton.
                rewrite FromList_apply_list. sets.
             ++ normalize_bound_var. sets.
             ++ intros. eapply preord_exp_app_compat.
                assumption. assumption.
                eapply H0. now constructor.
                eapply Forall2_preord_var_env_map. eassumption.
                now constructor.
        *  eapply return_triple.
           intros. split; [| split; [| split; [| split; [| split ]]]]; try eassumption.
           ++ reflexivity.
           ++ constructor.
           ++ simpl. repeat normalize_occurs_free. rewrite !image_Union, image_Singleton.
              rewrite FromList_apply_list. sets.
           ++ normalize_bound_var. sets.
           ++ intros. eapply preord_exp_app_compat.
              assumption. assumption.
              eapply H0. now constructor.
              eapply Forall2_preord_var_env_map. eassumption.
              now constructor.
    - (* Eprim *)
      admit.
    - (* Ehalt *)
      admit.
  Qed.