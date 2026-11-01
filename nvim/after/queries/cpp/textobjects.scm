; Function and class gestures configured in mini.ai.
(function_definition
  body: (compound_statement) @function.inner
  (#offset! @function.inner 0 1 0 -1)) @function.outer

(class_specifier
  body: (field_declaration_list) @class.inner
  (#offset! @class.inner 0 1 0 -1)) @class.outer

(struct_specifier
  body: (field_declaration_list) @class.inner
  (#offset! @class.inner 0 1 0 -1)) @class.outer

((compound_statement) @block.outer @block.inner
  (#offset! @block.inner 0 1 0 -1))

(if_statement
  consequence: (compound_statement) @conditional.inner) @conditional.outer

(switch_statement
  body: (compound_statement) @conditional.inner) @conditional.outer

(for_statement
  body: (_) @loop.inner) @loop.outer

(for_range_loop
  body: (_) @loop.inner) @loop.outer

(while_statement
  body: (_) @loop.inner) @loop.outer

(do_statement
  body: (_) @loop.inner) @loop.outer
