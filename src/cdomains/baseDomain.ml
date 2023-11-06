(** Full domain of {!Base} analysis. *)

open GoblintCil
module VD = ValueDomain.Compound
module BI = IntOps.BigIntOps

module NH = BatHashtbl.Make (Node)
let widen_vars = NH.create 113

module CPA0 =
struct
  module M0 = MapDomain.MapBot (Basetype.Variables) (VD)
  module M =
  struct
    include M0
    include MapDomain.PrintGroupable (Basetype.Variables) (VD) (M0)
  end
  include MapDomain.LiftTop (VD) (MapDomain.HashCached (M))
  let name () = "value domain"
end

module Vars = Queries.VS

module CPA (* : MapDomain.S with type key = Basetype.Variables.t and type value = VD.t *) =
struct
  module CPA = CPA0
  include Lattice.Prod (CPA) (Vars)

  type key = CPA.key
  type value = CPA.value

  let add k v (m, _) = (CPA.add k v m, Vars.empty ())
  let remove k (m, _) = (CPA.remove k m, Vars.empty ())
  let find k (m, _) = CPA.find k m
  let find_opt k (m, _) = CPA.find_opt k m
  let mem k (m, _) = CPA.mem k m
  let map f (m, _) = (CPA.map f m, Vars.empty ())
  let add_list xs (m, _) = (CPA.add_list xs m, Vars.empty ())
  let add_list_set ks v (m, _) = (CPA.add_list_set ks v m, Vars.empty ())
  let add_list_fun ks f (m, _) = (CPA.add_list_fun ks f m, Vars.empty ())
  let map2 f (m1, _) (m2, _) = (CPA.map2 f m1 m2, Vars.empty ())
  let long_map2 f (m1, _) (m2, _) = (CPA.long_map2 f m1 m2, Vars.empty ())
  let for_all f (m, _) = CPA.for_all f m
  let iter f (m, _) = CPA.iter f m
  let fold f (m, _) a = CPA.fold f m a
  let filter f (m, _) = (CPA.filter f m, Vars.empty ())
  let merge f (m1, _) (m2, _) = (CPA.merge f m1 m2, Vars.empty ())
  let leq_with_fct f (m1, _) (m2, _) = CPA.leq_with_fct f m1 m2
  let join_with_fct f (m1, v1) (m2, v2) = (CPA.join_with_fct f m1 m2, Vars.join v1 v2)
  let widen_with_fct f (m1, v1) (m2, _) =
    let vs = ref v1 in
    let f' k v1 v2 =
      match v1, v2 with
      | Some v1, Some v2 ->
        let v' = f v1 v2 in
        if not (VD.equal v2 v') then (
          ignore (Pretty.printf "widen %a at %a\n" Basetype.Variables.pretty k (Pretty.docOpt (Node.pretty_plain_short ())) !Node.current_node);
          NH.add widen_vars (Option.get !Node.current_node) k; (* TODO: remove *)
          vs := Vars.add k !vs;
        );
        Some v'
      | Some _, _ -> v1
      | _, Some _ -> v2
      | _ -> None
    in
    let m' = CPA0.merge f' m1 m2 in
    ignore (Pretty.printf "widen vars %a -> %a at %a\n" Vars.pretty v1 Vars.pretty !vs (Pretty.docOpt (Node.pretty_plain_short ())) !Node.current_node);
    (m', !vs)
  let narrow (m1, v1) (m2, _) =
    (CPA.narrow m1 m2, v1)
  let cardinal (m, _) = CPA.cardinal m
  let choose (m, _) = CPA.choose m
  let singleton k v = (CPA.singleton k v, Vars.empty ())
  let empty () = (CPA.empty (), Vars.empty ())
  let is_empty (m, _) = CPA.is_empty m
  let exists f (m, _) = CPA.exists f m
  let bindings (m, _) = CPA.bindings m
  let mapi f (m, _) = (CPA.mapi f m, Vars.empty ())
end

(* Keeps track of which arrays are potentially partitioned according to an expression containing a specific variable *)
(* Map from variables to sets of arrays: var -> {array} *)
module PartDeps =
struct
  module VarSet = SetDomain.Make(Basetype.Variables)
  include MapDomain.MapBot_LiftTop(Basetype.Variables)(VarSet)
  let name () = "array partitioning deps"
end

(** Maintains a set of local variables that need to be weakly updated, because multiple reachable copies of them may *)
(* exist on the call stack *)
module WeakUpdates =
struct
  include SetDomain.ToppedSet(Basetype.Variables) (struct let topname = "All variables weak" end)
  let name () = "Vars with Weak Update"
end


type 'a basecomponents_t = {
  cpa: CPA.t;
  deps: PartDeps.t;
  weak: WeakUpdates.t;
  priv: 'a;
} [@@deriving eq, ord, hash]


module BaseComponents (PrivD: Lattice.S):
sig
  include Lattice.S with type t = PrivD.t basecomponents_t
  val op_scheme: (CPA.t -> CPA.t -> CPA.t) -> (PartDeps.t -> PartDeps.t -> PartDeps.t) -> (WeakUpdates.t -> WeakUpdates.t -> WeakUpdates.t) -> (PrivD.t -> PrivD.t -> PrivD.t) -> t -> t -> t
end =
struct
  type t = PrivD.t basecomponents_t [@@deriving eq, ord, hash]

  include Printable.Std
  open Pretty

  let show r =
    let first  = CPA.show r.cpa in
    let second  = PartDeps.show r.deps in
    let third  = WeakUpdates.show r.weak in
    let fourth =  PrivD.show r.priv in
    "(" ^ first ^ ", " ^ second ^ ", " ^ third  ^ ", " ^ fourth  ^ ")"

  let pretty () r =
    text "(" ++
    CPA.pretty () r.cpa
    ++ text ", " ++
    PartDeps.pretty () r.deps
    ++ text ", " ++
    WeakUpdates.pretty () r.weak
    ++ text ", " ++
    PrivD.pretty () r.priv
    ++ text ")"

  let printXml f r =
    let e = XmlUtil.escape in
    BatPrintf.fprintf f "<value>\n<map>\n<key>\n%s\n</key>\n%a<key>\n%s\n</key>\n%a<key>\n%s\n</key>\n%a\n<key>\n%s\n</key>\n%a</map>\n</value>\n"
      (e @@ CPA.name ()) CPA.printXml r.cpa
      (e @@ PartDeps.name ()) PartDeps.printXml r.deps
      (e @@ WeakUpdates.name ()) WeakUpdates.printXml r.weak
      (e @@ PrivD.name ()) PrivD.printXml r.priv

  let to_yojson r =
    `Assoc [ (CPA.name (), CPA.to_yojson r.cpa); (PartDeps.name (), PartDeps.to_yojson r.deps); (WeakUpdates.name (), WeakUpdates.to_yojson r.weak); (PrivD.name (), PrivD.to_yojson r.priv) ]

  let name () = CPA.name () ^ " * " ^ PartDeps.name () ^ " * " ^ WeakUpdates.name ()  ^ " * " ^ PrivD.name ()

  let of_tuple(cpa, deps, weak, priv):t = {cpa; deps; weak; priv}
  let to_tuple r = (r.cpa, r.deps, r.weak, r.priv)

  let arbitrary () =
    let tr = QCheck.quad (CPA.arbitrary ()) (PartDeps.arbitrary ()) (WeakUpdates.arbitrary ()) (PrivD.arbitrary ()) in
    QCheck.map ~rev:to_tuple of_tuple tr

  let bot () = { cpa = CPA.bot (); deps = PartDeps.bot (); weak = WeakUpdates.bot (); priv = PrivD.bot ()}
  let is_bot {cpa; deps; weak; priv} = CPA.is_bot cpa && PartDeps.is_bot deps && WeakUpdates.is_bot weak && PrivD.is_bot priv
  let top () = {cpa = CPA.top (); deps = PartDeps.top ();  weak = WeakUpdates.top () ; priv = PrivD.bot ()}
  let is_top {cpa; deps; weak; priv} = CPA.is_top cpa && PartDeps.is_top deps && WeakUpdates.is_top weak && PrivD.is_top priv

  let leq {cpa=x1; deps=x2; weak=x3; priv=x4 } {cpa=y1; deps=y2; weak=y3; priv=y4} =
    CPA.leq x1 y1 && PartDeps.leq x2 y2 && WeakUpdates.leq x3 y3 && PrivD.leq x4 y4

  let pretty_diff () (({cpa=x1; deps=x2; weak=x3; priv=x4}:t),({cpa=y1; deps=y2; weak=y3; priv=y4}:t)): Pretty.doc =
    if not (CPA.leq x1 y1) then
      CPA.pretty_diff () (x1,y1)
    else if not (PartDeps.leq x2 y2) then
      PartDeps.pretty_diff () (x2,y2)
    else if not (WeakUpdates.leq x3 y3) then
      WeakUpdates.pretty_diff () (x3,y3)
    else
      PrivD.pretty_diff () (x4,y4)

  let op_scheme op1 op2 op3 op4 {cpa=x1; deps=x2; weak=x3; priv=x4} {cpa=y1; deps=y2; weak=y3; priv=y4}: t =
    {cpa = op1 x1 y1; deps = op2 x2 y2; weak = op3 x3 y3; priv = op4 x4 y4 }
  let join = op_scheme CPA.join PartDeps.join WeakUpdates.join PrivD.join
  let meet = op_scheme CPA.meet PartDeps.meet WeakUpdates.meet PrivD.meet
  let widen = op_scheme CPA.widen PartDeps.widen WeakUpdates.widen PrivD.widen
  let narrow = op_scheme CPA.narrow PartDeps.narrow WeakUpdates.narrow PrivD.narrow

  let relift {cpa; deps; weak; priv} =
    {cpa = CPA.relift cpa; deps = PartDeps.relift deps; weak = WeakUpdates.relift weak; priv = PrivD.relift priv}
end

module type ExpEvaluator =
sig
  type t
  val eval_exp: t  ->  Cil.exp -> IntOps.BigIntOps.t option
end

(* Takes a module for privatization component and a module specifying how expressions can be evaluated inside the domain and returns the domain *)
module DomFunctor (PrivD: Lattice.S) (ExpEval: ExpEvaluator with type t = BaseComponents (PrivD).t) =
struct
  include BaseComponents (PrivD)

  let join (one:t) (two:t): t =
    let cpa_join = CPA.join_with_fct (VD.smart_join (ExpEval.eval_exp one) (ExpEval.eval_exp two)) in
    op_scheme cpa_join PartDeps.join WeakUpdates.join PrivD.join one two

  let leq one two =
    let cpa_leq = CPA.leq_with_fct (VD.smart_leq (ExpEval.eval_exp one) (ExpEval.eval_exp two)) in
    cpa_leq one.cpa two.cpa && PartDeps.leq one.deps two.deps && WeakUpdates.leq one.weak two.weak && PrivD.leq one.priv two.priv

  let widen one two: t =
    let cpa_widen = CPA.widen_with_fct (VD.smart_widen (ExpEval.eval_exp one) (ExpEval.eval_exp two)) in
    op_scheme cpa_widen PartDeps.widen WeakUpdates.widen PrivD.widen one two
end


(* The domain with an ExpEval that only returns constant values for top-level vars that are definite ints *)
module DomWithTrivialExpEval (PrivD: Lattice.S) = DomFunctor (PrivD) (struct

  type t = BaseComponents (PrivD).t
  let eval_exp (r: t) e =
    match e with
    | Lval (Var v, NoOffset) ->
      begin
        match CPA.find v r.cpa with
        | Int i -> ValueDomain.ID.to_int i
        | _ -> None
      end
    | _ -> None
end)
