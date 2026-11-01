;; extends

"import" @keyword.import

"module" @keyword.type

"export" @keyword

; Named modules and partitions are not strings. Header imports inherit the
; string_literal / system_lib_string captures from C.
(module_name
  (identifier) @module
  (#set! priority 105))

(module_name
  "." @punctuation.delimiter)
