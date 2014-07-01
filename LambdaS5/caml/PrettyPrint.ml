let rec string_of_value st = function
| Values.Null -> "null"
| Values.Undefined -> "undefined"
| Values.Number f -> CoqUtils.implode (JsNumber.to_string f)
| Values.String s -> CoqUtils.implode s
| Values.True -> "true"
| Values.False -> "false"
| Values.ObjectLoc loc -> string_of_object_option st (Values.get_object_from_store st loc)
and string_of_value_option st = function
| Some v -> string_of_value st v
| None -> "<unset val>"
and string_of_object st obj =
  Printf.sprintf "{[#proto: %s, #class: %s, #extensible: %B, #primval: %s, #code: %s] %s}"
  (string_of_value st obj.Values.object_proto) (CoqUtils.implode obj.Values.object_class)
  (obj.Values.object_extensible) (string_of_value_option st obj.Values.object_prim_value)
  (string_of_expression_option obj.Values.object_code)
  (String.concat ", " (List.map
      (fun (name, attr) -> Printf.sprintf "'%s': %s" (CoqUtils.implode name) (string_of_attr st attr))
      (Values.Heap.to_list obj.Values.object_properties_)))
and string_of_object_option st = function
| Some obj -> string_of_object st obj
| None -> "<unexisting object>"
and string_of_expression e =
  "<expr>"
and string_of_expression_option = function
| Some e -> string_of_expression e
| None -> "<unset expr>"
and string_of_attr st = function
| Values.Coq_attributes_data_of d -> Values.attributes_data_rect (fun v w c e -> Printf.sprintf "{#value %s, #writable %B, #configurable %B, #enumerable %B}" (string_of_value st v) w c e) d
| Values.Coq_attributes_accessor_of d -> Values.attributes_accessor_rect (fun g s e c -> Printf.sprintf "{#getter %s, #setter %s}" (string_of_value st g) (string_of_value st s)) d (* enumerable and configurable ignored *)
