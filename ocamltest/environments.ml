(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*             Sebastien Hinderer, projet Gallium, INRIA Paris            *)
(*                                                                        *)
(*   Copyright 2016 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

(* Definition of environments, used to pass parameters to tests and actions *)

open Ocamltest_stdlib

module VariableMap = Map.Make (Variables)

type t = string VariableMap.t

let empty = VariableMap.empty

let to_bindings env =
  let f variable value lst = (variable, value) :: lst in
  VariableMap.fold f env []

let expand_aux env value =
  let bindings = to_bindings env in
  let f (variable, value) = ((Variables.name_of_variable variable), value) in
  let simple_bindings = List.map f bindings in
  let subst s = try (List.assoc s simple_bindings) with Not_found -> "" in
  let b = Buffer.create 100 in
  try Buffer.add_substitute b subst value; Buffer.contents b with _ -> value

let rec expand env value =
  let expanded = expand_aux env value in
  if expanded=value then value else expand env expanded

let to_system_env env =
  let system_env = Array.make (VariableMap.cardinal env) "" in
  let i = ref 0 in
  let store variable value =
    system_env.(!i) <-
      Variables.string_of_binding variable (expand env value);
    incr i in
  VariableMap.iter store env;
  system_env

let lookup variable env =
  try Some (expand env (VariableMap.find variable env)) with Not_found -> None

let lookup_nonempty variable env = match lookup variable env with
  | None -> None
  | Some x as t -> if String.words x = [] then None else t

let lookup_as_bool variable env =
  match lookup variable env with
  | None -> None
  | Some "true" -> Some true
  | Some _ -> Some false

let safe_lookup variable env = match lookup variable env with
  | None -> ""
  | Some value -> value

let is_variable_defined variable env =
  VariableMap.mem variable env

let add variable value env = VariableMap.add variable value env

let add_if_undefined variable value env =
  if VariableMap.mem variable env then env else add variable value env

let append variable appened_value environment =
  let previous_value = safe_lookup variable environment in
  let new_value = previous_value ^ appened_value in
  VariableMap.add variable new_value environment

let remove = VariableMap.remove

let add_bindings bindings env =
  let f env (variable, value) = add variable value env in
  List.fold_left f env bindings

let from_bindings bindings = add_bindings bindings empty

let dump_assignment log (variable, value) =
  Printf.fprintf log "%s = %s\n%!" (Variables.name_of_variable variable) value

let dump log environment =
  List.iter (dump_assignment log) (VariableMap.bindings environment)

(* Initializers *)

type env_initializer = out_channel -> t -> t

let (initializers : (string, env_initializer) Hashtbl.t) = Hashtbl.create 10

let register_initializer name code = Hashtbl.add initializers name code

let apply_initializer _log _name code env =
  code _log env

let initialize log env =
  let f = apply_initializer log in
  Hashtbl.fold f initializers env

(* Modifiers *)

type modifier =
  | Include of string
  | Add of Variables.t * string
  | Append of Variables.t * string
  | Remove of Variables.t

type modifiers = modifier list

exception Empty_modifiers_name
exception Modifiers_name_already_registered of string
exception Modifiers_name_not_found of string

let (registered_modifiers : (string, modifiers) Hashtbl.t) = Hashtbl.create 20

let register_modifiers name modifiers =
  if name="" then raise Empty_modifiers_name
  else if Hashtbl.mem registered_modifiers name
  then raise (Modifiers_name_already_registered name)
  else Hashtbl.add registered_modifiers name modifiers

let find_modifiers name =
  try Hashtbl.find registered_modifiers name
  with Not_found -> raise (Modifiers_name_not_found name)

let rec apply_modifier environment = function
  | Include modifiers_name ->
    apply_modifiers environment (find_modifiers modifiers_name)
  | Add (variable, value) -> add variable value environment
  | Append (variable, value) -> append variable value environment
  | Remove variable -> remove variable environment
and apply_modifiers environment modifiers =
  List.fold_left apply_modifier environment modifiers
