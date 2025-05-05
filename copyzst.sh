cd packages

for dir in */; do
  cp $dir*.zst ../builtpackages/
done