#!/usr/bin/env bash
# A7: classify GUT offline tests: source-text (reads .lua as text and greps) vs behavioural (dofile/loadfile executes module)
cd qa/lua/tests || exit 1
printf '%-52s %6s %6s %6s %6s %6s\n' file lines cases srcfind exec dev/stable
for f in test_gut_*.lua test_mod_tweaker_*.lua; do
  lines=$(wc -l < "$f")
  cases=$(grep -cE '^\s*(T\.|t\.|H\.|h\.)?(test|it|case|check)\s*\(|harness\.(test|case)\(|\btest\(\s*"' "$f")
  src=$(grep -cE ':find\(|:match\(|string\.find|read_source|read_file|io\.open|slurp|read_text|contains\(' "$f")
  exe=$(grep -cE 'loadfile|dofile|loadstring|load_module|load_mod_file|H\.load|harness\.load' "$f")
  ds=$( (grep -q 'gui_tweaker_dev' "$f" && printf d) ; (grep -qE 'gui_tweaker/|"gui_tweaker"|gui_tweaker\b[^_]' "$f" && printf s) )
  printf '%-52s %6s %6s %6s %6s %6s\n' "$f" "$lines" "$cases" "$src" "$exe" "$ds"
done
